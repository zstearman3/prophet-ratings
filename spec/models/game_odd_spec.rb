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
require 'rails_helper'

RSpec.describe GameOdd, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
