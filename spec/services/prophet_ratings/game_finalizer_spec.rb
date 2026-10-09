# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GameFinalizer, type: :service do
  describe '#update_derived_fields' do
    it 'sets in_conference false when both teams have missing conferences' do
      game = build_game_for_finalization

      described_class.new(game).send(:update_derived_fields)

      expect(game.reload.in_conference).to be(false)
    end

    it 'sets in_conference true when both teams have the same non-null conference' do
      conference = create(:conference, name: 'Shared Conference', slug: 'shared-conference')
      game = build_game_for_finalization
      create(:team_conference, team: game.home_team_season.team, conference:, start_season: game.season)
      create(:team_conference, team: game.away_team_season.team, conference:, start_season: game.season)

      described_class.new(game).send(:update_derived_fields)

      expect(game.reload.in_conference).to be(true)
    end

    it 'sets in_conference false when teams have different conferences' do
      game = build_game_for_finalization
      create(:team_conference, team: game.home_team_season.team, start_season: game.season)
      create(:team_conference, team: game.away_team_season.team, start_season: game.season)

      described_class.new(game).send(:update_derived_fields)

      expect(game.reload.in_conference).to be(false)
    end

    it 'sets in_conference false when only one team has a conference' do
      game = build_game_for_finalization
      create(:team_conference, team: game.home_team_season.team, start_season: game.season)

      described_class.new(game).send(:update_derived_fields)

      expect(game.reload.in_conference).to be(false)
    end

    def build_game_for_finalization
      season = create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10))
      home_team_season = create(:team_season, season:)
      away_team_season = create(:team_season, season:)
      game = create(:game, season:, home_team_name: home_team_season.team.school, away_team_name: away_team_season.team.school)
      create(:team_game, game:, team: home_team_season.team, team_season: home_team_season, home: true, minutes: 200)
      create(:team_game, game:, team: away_team_season.team, team_season: away_team_season, home: false, minutes: 200)
      game
    end
  end

  describe '#finalize_prediction!' do
    it 'does not update prediction when error attributes are unavailable' do
      version = create(:ratings_config_version)
      snapshot = create(:team_rating_snapshot, ratings_config_version: version)
      prediction = create(:prediction, game: create(:game, season: snapshot.season), ratings_config_version: version,
                                       home_team_snapshot: snapshot, away_team_snapshot: snapshot)
      game = prediction.game
      finalizer = described_class.new(game)
      allow(finalizer).to receive(:prediction_error_attributes).and_return(nil)
      original = prediction.attributes

      finalizer.send(:finalize_prediction!)

      expect(prediction.reload.attributes).to eq(original)
    end
  end

  describe 'invalid historical prediction provenance' do
    let(:season) { create(:season) }
    let(:version) { create(:ratings_config_version) }
    let(:other_version) { create(:ratings_config_version) }
    let(:game) { create(:game, season:, status: :scheduled, home_team_score: 80, away_team_score: 70) }
    let(:teams) { Array.new(2) { create(:team_season, season:) } }
    let!(:invalid) { stored_prediction(version, game.schedule_date - 1) }
    let!(:valid) { stored_prediction(other_version, game.schedule_date - 1) }

    def stored_prediction(model, date)
      home, away = teams.map do |team|
        create(:team_rating_snapshot, team_season: team, ratings_config_version: model, snapshot_date: date)
      end
      create(:prediction, game:, home_team_snapshot: home, away_team_snapshot: away, ratings_config_version: model,
                          home_offensive_efficiency: 100, away_offensive_efficiency: 100,
                          home_defensive_efficiency: 100, away_defensive_efficiency: 100, pace: 70)
    end

    before do
      teams.each_with_index do |team, index|
        create(:team_game, game:, team: team.team, team_season: team, opponent_team_season: teams[1 - index], home: index.zero?,
                           field_goals_attempted: 50, field_goals_made: 20, free_throws_attempted: 20,
                           two_pt_attempted: 40, two_pt_made: 15, three_pt_attempted: 10, three_pt_made: 5,
                           free_throws_made: 10, offensive_rebounds: 10, defensive_rebounds: 20,
                           rebounds: 30, turnovers: 10, points: index.zero? ? 80 : 70, minutes: 200)
      end
      invalid.update_columns(ratings_config_version_id: other_version.id) # rubocop:disable Rails/SkipsModelValidations
      allow(Rails.logger).to receive(:warn)
    end

    it 'logs and skips the invalid row during ingestion while finalizing valid predictions and the game' do
      original = invalid.attributes
      described_class.new(game).call
      expect(game.reload).to be_final
      expect(invalid.reload.attributes).to eq(original)
      expect(valid.reload.home_offensive_efficiency_error).not_to be_nil
      expect(Rails.logger).to have_received(:warn).with(/Skipping prediction=#{invalid.id} for game=#{game.id}/)
    end

    it 'raises and rolls back game finalization for a pinned run with the same invalid row' do
      expect do
        described_class.new(game, ratings_config_version: other_version).call
      end.to raise_error(ArgumentError, /selected model version/)
      expect(game.reload).to be_scheduled
      expect(game.possessions).to be_nil
      expect(valid.reload.home_offensive_efficiency_error).to be_nil
    end

    it 'also skips a historical prediction with no output model ID during ingestion' do
      invalid.update_columns(ratings_config_version_id: nil) # rubocop:disable Rails/SkipsModelValidations
      original = invalid.attributes
      described_class.new(game).call
      expect(game.reload).to be_final
      expect(invalid.reload.attributes).to eq(original)
      expect(valid.reload.pace_error).not_to be_nil
    end

    it 'propagates unrelated errors instead of treating them as invalid provenance' do
      finalizer = described_class.new(game)
      allow(finalizer).to receive(:update_prediction_errors!).and_raise(ArgumentError, 'bad error arithmetic')
      expect { finalizer.call }.to raise_error(ArgumentError, 'bad error arithmetic')
      expect(game.reload).to be_scheduled
    end
  end
end
