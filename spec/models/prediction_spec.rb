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
#  pace                            :decimal(6, 3)
#  pace_error                      :decimal(6, 3)
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  game_id                         :bigint           not null
#
# Indexes
#
#  index_predictions_on_game_id  (game_id)
#
require 'rails_helper'

RSpec.describe Prediction do
  pending "add some examples to (or delete) #{__FILE__}"
end
