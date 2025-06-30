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

  def formatted_home_line
    format_odds(spread_point)
  end

  def formatted_away_line
    format_odds(-spread_point)
  end

  def formatted_home_odds
    format_odds(spread_home_odds)
  end

  def formatted_away_odds
    format_odds(spread_away_odds)
  end

  def formatted_home_moneyline
    format_odds(moneyline_home)
  end

  def formatted_away_moneyline
    format_odds(moneyline_away)
  end

  def formatted_favorite_line
    if spread_point < 0
      "#{game.home_team_name} #{format_odds(spread_point)}"
    else
      "#{game.away_team_name} #{format_odds(-spread_point)}"
    end
  end

  private

  def format_odds(odds)
    odds > 0 ? "+#{odds}" : odds
  end
end
