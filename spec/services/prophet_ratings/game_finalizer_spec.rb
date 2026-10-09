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
end
