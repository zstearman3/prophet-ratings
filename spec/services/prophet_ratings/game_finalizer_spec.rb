# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GameFinalizer, type: :service do
  describe '#call box-score integrity' do
    let(:season) { create(:season) }
    let(:game) { create(:game, season:, status: :scheduled, home_team_score: 55, away_team_score: 55) }
    let(:box) do
      { minutes: 200, field_goals_made: 20, field_goals_attempted: 50,
        two_pt_made: 15, two_pt_attempted: 40, three_pt_made: 5, three_pt_attempted: 10,
        free_throws_made: 10, free_throws_attempted: 20, offensive_rebounds: 10,
        defensive_rebounds: 20, rebounds: 30, assists: 12, steals: 5, blocks: 3,
        turnovers: 10, fouls: 15, points: 55 }
    end
    let!(:home) { create_side(true) }
    let!(:away) { create_side(false) }

    def create_side(home)
      team_season = create(:team_season, season:)
      create(:team_game, game:, team_season:, team: team_season.team, home:, **box)
    end

    [[:minutes, nil], [:minutes, 0], [:minutes, -5], [:turnovers, nil], [:turnovers, -1],
     [:points, nil], [:points, -1], [:points, 56], [:field_goals_made, 21],
     [:field_goals_attempted, 51], [:two_pt_made, 41], [:three_pt_made, 11],
     [:free_throws_made, 21], [:rebounds, 31]].each do |field, value|
      it "rejects invalid home #{field}=#{value.inspect} before writing derived fields" do
        home.update!(field => value)
        expect { described_class.new(game).call }.to raise_error(described_class::MissingDerivedStatsError, /game #{game.id}.*home/)
        expect(game.reload).to have_attributes(status: 'scheduled', minutes: nil, possessions: nil)
        expect(home.reload.offensive_rating).to be_nil
      end
    end

    invalid_scores = [nil, -1, 54]
    %i[home_team_score away_team_score].each do |field|
      invalid_scores.each do |value|
        it "rejects invalid #{field}=#{value.inspect}" do
          game.update!(field => value)
          expect { described_class.new(game).call }.to raise_error(described_class::MissingDerivedStatsError, /score/)
          expect(game.reload).to be_scheduled
        end
      end
    end

    [true, false].each do |missing_home|
      it "requires the #{missing_home ? 'home' : 'away'} side" do
        (missing_home ? home : away).destroy!
        expect { described_class.new(game.reload).call }.to raise_error(described_class::MissingDerivedStatsError, /side/)
        expect(game.reload.possessions).to be_nil
      end
    end

    it 'rejects differing side minute totals' do
      away.update!(minutes: 225)
      expect { described_class.new(game).call }.to raise_error(described_class::MissingDerivedStatsError, /minutes/)
    end

    [0, -1, Float::NAN, Float::INFINITY].each do |possessions|
      it "rejects #{possessions.inspect} possessions on one side even when the average would look usable" do
        allow(game.home_team_game).to receive(:calculated_possessions).and_return(possessions)
        expect { described_class.new(game).call }.to raise_error(described_class::MissingDerivedStatsError, /home.*possessions/)
        expect(game.reload.possessions).to be_nil
      end
    end

    it 'rejects nonfinite derived pace' do
      allow(game).to receive(:pace).and_return(Float::INFINITY)
      expect { described_class.new(game).call }.to raise_error(described_class::MissingDerivedStatsError, /pace/)
      expect(game.reload.possessions).to be_nil
    end

    it 'rejects the reported score/count mismatch even with positive turnover-based possessions' do
      zero_box = box.transform_values { 0 }.merge(minutes: 200, turnovers: 10)
      [home, away].each { |side| side.update!(zero_box) }
      game.update!(home_team_score: 1, away_team_score: 0)
      expect { described_class.new(game).call }.to raise_error(described_class::MissingDerivedStatsError, /home.*score/)
    end

    it 'finalizes consistent zero-opportunity boxes without fabricated rates' do
      zero_box = box.transform_values { 0 }.merge(minutes: 200, turnovers: 10)
      [home, away].each { |side| side.update!(zero_box) }
      game.update!(home_team_score: 0, away_team_score: 0)
      described_class.new(game).call
      expect(game.reload).to have_attributes(status: 'final', minutes: 40, possessions: 10, pace: 10)
      expect(home.reload).to have_attributes(field_goals_percentage: nil, three_pt_percentage: nil,
                                             true_shooting_percentage: nil, offensive_rebound_rate: nil,
                                             assist_rate: nil, turnover_rate: 1, offensive_rating: 0)
    end

    it 'preserves overtime minutes and 40-minute pace with independently checked possessions' do
      [home, away].each { |side| side.update!(minutes: 225) }
      described_class.new(game).call
      # 50 FGA - 10 ORB + 10 TOV + .475 * 20 FTA = 59.5 possessions.
      expect(game.reload).to have_attributes(status: 'final', minutes: 45, possessions: 59.5)
      expect(game.pace).to be_within(0.00001).of(52.8888889)
      expect(home.reload.offensive_rating).to eq(92.437)
    end

    it 'rolls back game and first-side writes if the second side cannot save, even when rescued in an outer transaction' do
      game.away_team_game.team = nil
      Game.transaction do
        expect { described_class.new(game).call }.to raise_error(ActiveRecord::RecordInvalid)
        Game.find(game.id).update!(venue_name: 'Outer transaction survives')
      end
      expect(game.reload).to have_attributes(status: 'scheduled', minutes: nil, possessions: nil,
                                             venue_name: 'Outer transaction survives')
      expect(home.reload.offensive_rating).to be_nil
      expect(away.reload.offensive_rating).to be_nil
    end

    it 'rolls back team stats and prediction errors when the final status save fails' do
      version = create(:ratings_config_version)
      snapshots = [home, away].map do |side|
        create(:team_rating_snapshot, team_season: side.team_season, ratings_config_version: version,
                                      snapshot_date: game.schedule_date - 1)
      end
      prediction = create(:prediction, game:, ratings_config_version: version,
                                       home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                                       home_offensive_efficiency: 100, away_offensive_efficiency: 100,
                                       home_defensive_efficiency: 100, away_defensive_efficiency: 100, pace: 70)
      allow(game).to receive(:final!).and_raise(ActiveRecord::RecordInvalid.new(game))
      Game.transaction do
        expect { described_class.new(game).call }.to raise_error(ActiveRecord::RecordInvalid)
      end
      expect(game.reload).to have_attributes(status: 'scheduled', minutes: nil, possessions: nil)
      expect(home.reload.offensive_rating).to be_nil
      expect(prediction.reload.home_offensive_efficiency_error).to be_nil
    end
  end

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
      allow(described_class).to receive(:prediction_error_attributes).and_return(nil)
      original = prediction.attributes

      finalizer.send(:finalize_prediction!)

      expect(prediction.reload.attributes).to eq(original)
    end
  end

  describe 'invalid historical prediction provenance' do
    let(:season) { create(:season) }
    let(:version) { create(:ratings_config_version) }
    let(:other_version) { create(:ratings_config_version) }
    let(:game) { create(:game, season:, status: :scheduled, home_team_score: 55, away_team_score: 55) }
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
                           rebounds: 30, turnovers: 10, points: 55, minutes: 200, assists: 12, steals: 5, blocks: 3, fouls: 15)
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
