# frozen_string_literal: true

# == Schema Information
#
# Table name: game_odds
#
#  id               :bigint           not null, primary key
#  fetched_at       :datetime         not null
#  moneyline_away   :integer
#  moneyline_home   :integer
#  spread_away_odds :integer
#  spread_home_odds :integer
#  spread_point     :decimal(, )
#  total_over_odds  :integer
#  total_points     :decimal(, )
#  total_under_odds :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  game_id          :bigint           not null
#
# Indexes
#
#  index_game_odds_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
class GameOdd < ApplicationRecord
  belongs_to :game
  validates :game_id, uniqueness: true
  has_many :bet_recommendations, dependent: :destroy

  ##
  # Returns the home team's spread line formatted as an odds string.
  # @return [String] The formatted home spread line.
  def formatted_home_line
    format_odds(spread_point)
  end

  ##
  # Returns the away team's spread line formatted as odds, using the negated spread point.
  def formatted_away_line
    format_odds(-spread_point)
  end

  ##
  # Returns the formatted spread odds for the home team, prefixing positive values with a plus sign.
  def formatted_home_odds
    format_odds(spread_home_odds)
  end

  ##
  # Returns the formatted spread odds for the away team.
  # @return [String] The away team's spread odds with appropriate sign formatting.
  def formatted_away_odds
    format_odds(spread_away_odds)
  end

  ##
  # Returns the formatted moneyline odds for the home team.
  # @return [String] The home team's moneyline odds with a plus sign for positive values.
  def formatted_home_moneyline
    format_odds(moneyline_home)
  end

  ##
  # Returns the formatted moneyline odds for the away team, prefixing positive values with a plus sign.
  def formatted_away_moneyline
    format_odds(moneyline_away)
  end

  ##
  # Returns the favorite team's name and its formatted spread line.
  # The favorite is determined by the sign of the spread point: if negative, the home team is favored; otherwise, the away team is favored.
  # @return [String] The favorite team's name followed by its formatted spread line.
  def formatted_favorite_line
    if spread_point.negative?
      "#{game.home_team_name} #{format_odds(spread_point)}"
    else
      "#{game.away_team_name} #{format_odds(-spread_point)}"
    end
  end

  private

  ##
  # Formats an odds value by prefixing a plus sign if the value is positive.
  # @param [Integer] odds - The odds value to format.
  # @return [String, Integer] The formatted odds as a string with a plus sign for positive values, or the original value for zero or negative odds.
  def format_odds(odds)
    odds.positive? ? "+#{odds}" : odds
  end
end
