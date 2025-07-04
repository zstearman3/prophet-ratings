# frozen_string_literal: true

# == Schema Information
#
# Table name: bet_recommendations
#
#  id                                                                :bigint           not null, primary key
#  bet_type('moneyline', 'spread', or 'total')                       :string           not null
#  confidence(optional: model confidence (0.0–1.0 or 0–100 scale)) :float
#  current                                                           :boolean          default(FALSE)
#  ev(expected value (unit-neutral, e.g. +0.07 = +7%))               :float            not null
#  model_value(model-predicted value (spread, total, or win %))      :float            not null
#  payout(net return in units, e.g. +0.91, -1.00)                    :float
#  recommended(whether the bet is actionable)                        :boolean          default(FALSE), not null
#  result('win', 'loss', 'push')                                     :string
#  team('home', 'away', 'over', 'under')                             :string
#  vegas_line(point spread or total; nil for moneyline)              :float
#  vegas_odds(payout in American odds (e.g. -110, +150))             :integer          not null
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  game_id                                                           :bigint           not null
#  game_odd_id                                                       :bigint           not null
#  prediction_id                                                     :bigint           not null
#  ratings_config_version_id                                         :bigint
#
# Indexes
#
#  index_bet_recommendations_on_game_id                    (game_id)
#  index_bet_recommendations_on_game_odd_id                (game_odd_id)
#  index_bet_recommendations_on_prediction_id              (prediction_id)
#  index_bet_recommendations_on_ratings_config_version_id  (ratings_config_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#  fk_rails_...  (game_odd_id => game_odds.id)
#  fk_rails_...  (prediction_id => predictions.id)
#  fk_rails_...  (ratings_config_version_id => ratings_config_versions.id)
#
class BetRecommendation < ApplicationRecord
  belongs_to :ratings_config_version
  belongs_to :game
  belongs_to :prediction
  belongs_to :game_odd

  validates :bet_type, uniqueness: { scope: %i[prediction_id game_odd_id] }
  validates :bet_type, inclusion: { in: ->(rec) { rec.class.bet_types.keys } }
  validates :team, inclusion: { in: ->(rec) { rec.class.teams.keys } }, allow_nil: true

  enum bet_type: {
    moneyline: 'moneyline',
    spread: 'spread',
    total: 'total'
  }, _suffix: true

  enum team: {
    home: 'home',
    away: 'away',
    over: 'over',
    under: 'under'
  }, _suffix: true

  ##
  # Returns a formatted string describing the recommended bet, including team name and odds or line, or "No play" if not recommended.
  # @return [String] The bet recommendation description or "No play".
  def recommendation
    return 'No play' unless recommended && team.present?

    case team
    when 'home'
      if bet_type == 'spread'
        "#{game.home_team_name} #{game_odd.formatted_home_line}"
      else
        "#{game.home_team_name} #{game_odd.formatted_home_moneyline}"
      end
    when 'away'
      if bet_type == 'spread'
        "#{game.away_team_name} #{game_odd.formatted_away_line}"
      else
        "#{game.away_team_name} #{game_odd.formatted_away_moneyline}"
      end
    when 'over'
      "Over #{game_odd.total_points}"
    when 'under'
      "Under #{game_odd.total_points}"
    end
  end
end
