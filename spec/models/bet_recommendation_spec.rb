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
#  index_bet_recommendations_on_game_id                       (game_id)
#  index_bet_recommendations_on_game_odd_id                   (game_odd_id)
#  index_bet_recommendations_on_prediction_game_odd_bet_type  (prediction_id,game_odd_id,bet_type) UNIQUE
#  index_bet_recommendations_on_prediction_id                 (prediction_id)
#  index_bet_recommendations_on_ratings_config_version_id     (ratings_config_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#  fk_rails_...  (game_odd_id => game_odds.id)
#  fk_rails_...  (prediction_id => predictions.id)
#  fk_rails_...  (ratings_config_version_id => ratings_config_versions.id)
#
require 'rails_helper'

RSpec.describe BetRecommendation do
  pending "add some examples to (or delete) #{__FILE__}"
end
