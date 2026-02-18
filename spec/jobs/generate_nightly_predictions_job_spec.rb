# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateNightlyPredictionsJob do
  let(:as_of) { Time.zone.parse('2026-02-01 10:00:00') }
  let(:season) do
    create(
      :season,
      year: 2026,
      start_date: Date.new(2025, 11, 1),
      end_date: Date.new(2026, 4, 1)
    )
  end
  let(:current_config) { create(:ratings_config_version, current: true) }
  let(:older_config) { create(:ratings_config_version, current: false) }

  it 'generates predictions for final games missing current-config predictions and scheduled games in the next week' do
    final_missing = create(:game, season:, status: :final, start_time: as_of - 2.days)
    final_with_current = create(:game, season:, status: :final, start_time: as_of - 1.day)
    final_with_old_only = create(:game, season:, status: :final, start_time: as_of - 3.days)
    scheduled_next_week = create(:game, season:, status: :scheduled, start_time: as_of + 3.days)
    scheduled_with_current = create(:game, season:, status: :scheduled, start_time: as_of + 5.days)
    scheduled_outside_window = create(:game, season:, status: :scheduled, start_time: as_of + 8.days)

    create_prediction_for(game: final_with_current, ratings_config_version: current_config)
    create_prediction_for(game: final_with_old_only, ratings_config_version: older_config)
    create_prediction_for(game: scheduled_with_current, ratings_config_version: current_config)

    prediction_builder = instance_double(ProphetRatings::GamePredictionBuilder, call: true)
    generated_game_ids = []
    allow(ProphetRatings::GamePredictionBuilder).to receive(:new) do |game|
      generated_game_ids << game.id
      prediction_builder
    end

    described_class.perform_now(season.id, as_of:)

    expect(generated_game_ids).to contain_exactly(
      final_missing.id,
      final_with_old_only.id,
      scheduled_next_week.id,
      scheduled_with_current.id
    )
    expect(generated_game_ids).not_to include(final_with_current.id, scheduled_outside_window.id)
  end

  def create_prediction_for(game:, ratings_config_version:)
    home_team_season = create(:team_season, season: game.season)
    away_team_season = create(:team_season, season: game.season)
    home_snapshot = create(
      :team_rating_snapshot,
      team_season: home_team_season,
      team: home_team_season.team,
      season: game.season,
      ratings_config_version:,
      snapshot_date: game.start_time.to_date - 1.day
    )
    away_snapshot = create(
      :team_rating_snapshot,
      team_season: away_team_season,
      team: away_team_season.team,
      season: game.season,
      ratings_config_version:,
      snapshot_date: game.start_time.to_date - 1.day
    )

    create(
      :prediction,
      game:,
      home_team_snapshot: home_snapshot,
      away_team_snapshot: away_snapshot,
      ratings_config_version:
    )
  end
end
