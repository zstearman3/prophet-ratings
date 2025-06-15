# frozen_string_literal: true

# == Schema Information
#
# Table name: bookmaker_odds
#
#  id         :bigint           not null, primary key
#  bookmaker  :string           not null
#  fetched_at :datetime         not null
#  market     :string           not null
#  odds       :integer
#  team_name  :string
#  team_side  :string
#  value      :decimal(, )
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  game_id    :bigint           not null
#
# Indexes
#
#  index_bookmaker_odds_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
require 'rails_helper'

RSpec.describe BookmakerOdd do
  pending "add some examples to (or delete) #{__FILE__}"
end
