# frozen_string_literal: true

# == Schema Information
#
# Table name: games
#
#  id              :bigint           not null, primary key
#  away_team_name  :string           not null
#  away_team_score :integer
#  home_team_name  :string           not null
#  home_team_score :integer
#  in_conference   :boolean          default(FALSE)
#  location        :string
#  minutes         :integer
#  neutral         :boolean
#  possessions     :decimal(4, 1)
#  start_time      :datetime         not null
#  status          :integer          default("scheduled"), not null
#  url             :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  season_id       :bigint           not null
#
# Indexes
#
#  index_games_on_season_id  (season_id)
#
require 'rails_helper'

RSpec.describe Game do
  let(:season) { create(:season, :current, average_efficiency: 100.0, average_pace: 70.0) }
  let(:game) { create(:game, season:, start_time: Time.zone.today) }
  let(:home_team_season) { create(:team_season, season:) }
  let(:away_team_season) { create(:team_season, season:) }
  let(:ratings_config_version) { create(:ratings_config_version, current: true) }
  let!(:home_snapshot) do
    create(:team_rating_snapshot,
           team_season: home_team_season,
           snapshot_date: game.start_time.to_date,
           ratings_config_version:,
           adj_offensive_efficiency: 110.0,
           adj_defensive_efficiency: 105.0,
           adj_pace: 72.0)
  end
  let!(:away_snapshot) do
    create(:team_rating_snapshot,
           team_season: away_team_season,
           snapshot_date: game.start_time.to_date,
           ratings_config_version:,
           adj_offensive_efficiency: 108.0,
           adj_defensive_efficiency: 107.0,
           adj_pace: 68.0)
  end

  before do
    # Ensure associations are set up for the game if needed
    allow(game).to receive_messages(home_team_season:, away_team_season:, home_team_game: nil,
                                    away_team_game: nil)
  end

  describe '#generate_prediction!' do
    it 'creates a prediction for the game' do
      expect do
        game.generate_prediction!
      end.to change(Prediction, :count).by(1)
      prediction = Prediction.last
      expect(prediction.game).to eq(game)
      expect(prediction.home_team_snapshot).to eq(home_snapshot)
      expect(prediction.away_team_snapshot).to eq(away_snapshot)
    end
  end

  describe '#finalize' do
    it 'delegates to ProphetRatings::GameFinalizer' do
      finalizer_double = instance_double(ProphetRatings::GameFinalizer)
      expect(ProphetRatings::GameFinalizer).to receive(:new).with(game).and_return(finalizer_double)
      expect(finalizer_double).to receive(:call)
      game.finalize
    end
  end
end
