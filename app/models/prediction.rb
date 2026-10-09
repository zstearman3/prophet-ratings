# frozen_string_literal: true

# == Schema Information
#
# Table name: predictions
#
#  id                              :bigint           not null, primary key
#  away_defensive_efficiency       :decimal(6, 3)
#  away_defensive_efficiency_error :decimal(6, 3)
#  away_offensive_efficiency       :decimal(6, 3)
#  away_offensive_efficiency_error :decimal(6, 3)
#  away_score                      :decimal(6, 3)
#  home_defensive_efficiency       :decimal(6, 3)
#  home_defensive_efficiency_error :decimal(6, 3)
#  home_offensive_efficiency       :decimal(6, 3)
#  home_offensive_efficiency_error :decimal(6, 3)
#  home_score                      :decimal(6, 3)
#  home_win_probability            :decimal(5, 4)
#  pace                            :decimal(6, 3)
#  pace_error                      :decimal(6, 3)
#  vegas_spread                    :decimal(6, 3)
#  vegas_total                     :decimal(6, 3)
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  away_team_snapshot_id           :bigint
#  game_id                         :bigint           not null
#  home_team_snapshot_id           :bigint
#  ratings_config_version_id       :bigint
#
# Indexes
#
#  index_predictions_on_away_team_snapshot_id      (away_team_snapshot_id)
#  index_predictions_on_game_and_snapshots         (game_id,home_team_snapshot_id,away_team_snapshot_id) UNIQUE
#  index_predictions_on_game_id                    (game_id)
#  index_predictions_on_home_team_snapshot_id      (home_team_snapshot_id)
#  index_predictions_on_ratings_config_version_id  (ratings_config_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (away_team_snapshot_id => team_rating_snapshots.id)
#  fk_rails_...  (home_team_snapshot_id => team_rating_snapshots.id)
#  fk_rails_...  (ratings_config_version_id => ratings_config_versions.id)
#
class Prediction < ApplicationRecord
  belongs_to :game
  belongs_to :home_team_snapshot, class_name: 'TeamRatingSnapshot'
  belongs_to :away_team_snapshot, class_name: 'TeamRatingSnapshot'
  belongs_to :ratings_config_version
  has_one :home_team_game, through: :game
  has_one :away_team_game, through: :game
  has_one :season, through: :game
  has_many :bet_recommendations, dependent: :destroy

  validates :game, uniqueness: { scope: %i[home_team_snapshot_id away_team_snapshot_id] }
  validate :snapshots_must_have_same_ratings_version

  def favorite
    home_score > away_score ? game.home_team_game&.team : game.away_team_game&.team
  end

  def win_probability_for_team(team_id)
    home_team_snapshot.team_id == team_id ? home_win_probability : (1.0 - home_win_probability)
  end

  def favorite_win_probability
    home_score > away_score ? home_win_probability : (1.0 - home_win_probability)
  end

  def total
    ((home_score + away_score) * 2).round / 2.0
  end

  def correct?
    predicted_home_win = home_win_probability >= 0.5
    actual_home_win = game.home_team_score > game.away_team_score

    predicted_home_win == actual_home_win
  end

  ##
  # Returns a string representation of the predicted score,
  # adjusting to avoid displaying a tie by incrementing one team's score if the rounded scores are equal but the raw scores differ.
  # @return [String] The formatted predicted score as "away - home".
  def predicted_score_string
    away, home = adjusted_predicted_scores
    "#{away} - #{home}"
  end

  # Returns a formatted string showing the predicted scores for both teams with their names,
  # using the same tie-breaking logic as predicted_score_string.
  ##
  # Returns a formatted string showing each team's name and its predicted score, using tie-breaking logic to avoid displaying a tie when raw predicted scores differ.
  # @return [String] Predicted scores with team names, formatted as "AwayTeam score - HomeTeam score".
  def predicted_score_with_teams
    away, home = adjusted_predicted_scores
    "#{game.away_team_name} #{away} - #{game.home_team_name} #{home}"
  end

  # Shared-pace versions use exact product moments; legacy versions retain fixed-pace arithmetic.
  def margin_std_deviation
    return Math.sqrt(score_moments.margin_variance) if shared_pace_model?

    values = ProphetRatings::ModelConfiguration.snapshot_volatilities([home_team_snapshot, away_team_snapshot], ratings_config_version)
    Math.sqrt(values.sum { |value| value**2 } * pace_factor)
  end

  # Scores covary through pace, so total and margin uncertainty differ.
  def total_std_deviation
    return Math.sqrt(score_moments.total_variance) if shared_pace_model?

    values = ProphetRatings::ModelConfiguration.snapshot_volatilities([home_team_snapshot, away_team_snapshot], ratings_config_version)
    Math.sqrt(values.sum { |value| value**2 }) * pace_factor
  end

  # Returns [away_score, home_score] as integers, using tie-breaking logic if needed.
  def adjusted_predicted_scores
    home_score_rounded = home_score.round
    away_score_rounded = away_score.round
    if home_score_rounded == away_score_rounded
      if home_score > away_score
        [away_score_rounded, home_score_rounded + 1]
      else
        [away_score_rounded + 1, home_score_rounded]
      end
    else
      [away_score_rounded, home_score_rounded]
    end
  end

  ##
  # Calculates the pace factor as the square of the pace divided by 10,000.
  # @return [Float] The computed pace factor.
  def pace_factor
    (pace**2) / 10_000.0
  end

  ##
  # Returns a string indicating the favorite team and the predicted point spread based on rounded scores.
  # The point spread is negative if the home team is favored, positive if the away team is favored.
  # @return [String] The favorite team's name followed by the point spread.
  def favorite_line
    if home_score > away_score
      "#{game.home_team_name} #{away_score.round - home_score.round}"
    else
      "#{game.away_team_name} #{home_score.round - away_score.round}"
    end
  end

  private

  def shared_pace_model?
    ratings_config_version.config.dig('prediction', 'uncertainty_model') == 'shared_pace_v1'
  end

  def score_moments
    snapshots = [home_team_snapshot, away_team_snapshot]
    ProphetRatings::ModelConfiguration.snapshot_volatilities(snapshots, ratings_config_version)
    ProphetRatings::ModelConfiguration.validate_volatilities(snapshots.map(&:pace_volatility))
    calculator = ProphetRatings::VolatilityCalculator.new(
      home_rating_snapshot: home_team_snapshot, away_rating_snapshot: away_team_snapshot,
      season: season, ratings_config_version: ratings_config_version
    )
    ProphetRatings::ScoreMoments.new(
      means: { home: home_offensive_efficiency, away: away_offensive_efficiency, pace: pace },
      deviations: { home: calculator.total_home_volatility, away: calculator.total_away_volatility,
                    pace: calculator.total_pace_volatility }
    )
  end

  ##
  # Validates that the home and away team snapshots reference the same ratings configuration version.
  # Adds a validation error if the snapshots use different ratings config versions.
  def snapshots_must_have_same_ratings_version
    return if home_team_snapshot.nil? || away_team_snapshot.nil?

    version_ids = [home_team_snapshot.ratings_config_version_id, away_team_snapshot.ratings_config_version_id]
    return if version_ids.uniq.size == 1 && (ratings_config_version_id.nil? || version_ids.first == ratings_config_version_id)

    errors.add(:base, 'Home and away team snapshots must use the selected ratings config version')
  end
end
