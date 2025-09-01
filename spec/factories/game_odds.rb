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
#  index_game_odds_on_game_id         (game_id)
#  index_game_odds_on_game_id_unique  (game_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
FactoryBot.define do
  factory :game_odd
end
