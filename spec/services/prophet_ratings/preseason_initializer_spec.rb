# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonInitializer do
  before { RatingsConfigVersion.publish! }

  let(:season) { create(:season, average_pace: nil, average_efficiency: nil) }
  let!(:home) { create(:team_season, season:, offensive_efficiency_volatility: nil, defensive_efficiency_volatility: nil) }
  let!(:away) { create(:team_season, season:, offensive_efficiency_volatility: nil, defensive_efficiency_volatility: nil) }
  let(:initializer) { described_class.new(season) }

  def scheduled_game
    game = create(:game, season:, status: :scheduled, start_time: season.start_date.in_time_zone + 12.hours)
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
    game
  end

  it 'publishes defaults, deterministic tied ranks and captured snapshots before opening day' do
    initializer.call
    expect([home.reload.overall_rank, away.reload.overall_rank]).to eq([1, 2])
    expect([home.adj_offensive_efficiency, home.adj_pace, home.total_volatility,
            home.pace_volatility, home.total_home_boost, home.adj_effective_fg_percentage_rank]).to eq([105.5, 69.5, 11.5, 4.5, 4.4, nil])
    expect(TeamRatingSnapshot.count).to eq(2)
    snapshot = home.team_rating_snapshots.first
    expect([snapshot.snapshot_date, snapshot.ratings_config_version, snapshot.overall_rank])
      .to eq([season.start_date - 1, RatingsConfigVersion.find_or_create_by_current_config, 1])
    expect(snapshot.stats.dig('preseason_prior', 'outputs', 'preseason_adj_pace')).to eq(69.5)
  end

  it 'uses matching-version inputs while reporting the currently linked capture as before provenance' do
    original_version = RatingsConfigVersion.publish!
    described_class.new(season, ratings_config_version: original_version).call
    linked_prior = home.reload.preseason_prior
    selected_version = RatingsConfigVersion.publish!(RatingsConfigVersion.authored_config.merge(bundle_name: 'report-selection-test'))

    report = described_class.new(season, ratings_config_version: selected_version).send(:captured_report)
    team = report[:teams].find { |row| row[:team_id] == home.team_id }

    expect(team[:inputs]['configuration']['bundle_name']).to eq('report-selection-test')
    expect(team[:outputs_before]).to eq(linked_prior.outputs)
    expect(team[:profile_before]).to eq(linked_prior.inputs['profile'])
    expect(report[:teams].pluck(:team_id)).to eq([home, away].map(&:team_id).sort)
  end

  it 'produces a neutral scheduled prediction with independently calculated scores and probability' do
    game = scheduled_game
    initializer.call
    prediction = ProphetRatings::GamePredictionBuilder.new(game).call
    # 105.5 points per 100 possessions * 69.5 possessions = 73.3225 each.
    expect([prediction.home_score, prediction.away_score]).to eq([73.32, 73.32])
    expect(prediction.home_win_probability).to eq(0.5)
    ids = TeamRatingSnapshot.order(:id).pluck(:id)
    initializer.call
    expect(TeamRatingSnapshot.order(:id).pluck(:id)).to eq(ids)
    expect(ProphetRatings::GamePredictionBuilder.new(game).call.id).to eq(prediction.id)
    expect([home.reload.overall_rank, away.reload.overall_rank]).to eq([1, 2])
  end

  it 'uses an explicitly selected published model even when a different bundle has the global current flag' do
    version = RatingsConfigVersion.default_version
    stale = create(:ratings_config_version, current: true)
    game = scheduled_game
    described_class.new(season, ratings_config_version: version).call
    prediction = ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: version).call
    expect(prediction.ratings_config_version).to eq(version)
    expect(stale.reload).to be_current
  end

  it 'keeps zero-game prediction inputs usable after an opening-day ratings update' do
    game = scheduled_game
    initializer.call
    ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: season.start_date)
    prediction = ProphetRatings::GamePredictionBuilder.new(game.reload).call
    expect([prediction.home_score, prediction.away_score, prediction.home_win_probability]).to eq([73.32, 73.32, 0.5])
    expect(home.reload.overall_rank).to eq(1)
  end

  it 'explicitly skips missing or incomplete prediction inputs' do
    game = scheduled_game
    allow(Rails.logger).to receive(:warn)
    expect(ProphetRatings::GamePredictionBuilder.new(game).call).to be_nil
    initializer.call
    home.team_rating_snapshots.first.update!(adj_pace: nil)
    expect(ProphetRatings::GamePredictionBuilder.new(game).call).to be_nil
    expect(Prediction.count).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(/missing or invalid rating inputs/).twice
  end

  it 'rolls back priors, live values, defaults and snapshots after a partial publication failure' do
    service = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise('failed publication')
    expect { initializer.call }.to raise_error('failed publication')
    expect(home.reload.adj_pace).to be_nil
    expect(season.reload.average_efficiency).to be_nil
    expect(PreseasonPrior.count).to eq(0)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'rolls back publication even when an outer transaction rescues the failure and then permits a retry' do
    service = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise('failed publication')
    Season.transaction do
      expect { initializer.call }.to raise_error('failed publication')
    end
    expect([home.reload.adj_pace, season.reload.average_efficiency, PreseasonPrior.count, TeamRatingSnapshot.count])
      .to eq([nil, nil, 0, 0])
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_call_original
    initializer.call
    expect(TeamRatingSnapshot.count).to eq(2)
  end

  it 'rejects a direct publication call after activation without changing outputs' do
    initializer.call
    season.set_current!
    original = TeamRatingSnapshot.order(:id).map(&:attributes)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    expect(TeamRatingSnapshot.order(:id).map(&:attributes)).to eq(original)
    expect(season.reload).to be_current
  end

  %i[efficiency pace].each do |baseline|
    it "rejects a repeat that would change the #{baseline} baseline with saved predictions and rolls back new captures" do
      game = scheduled_game
      initializer.call
      prediction = ProphetRatings::GamePredictionBuilder.new(game).call
      original = [season.reload.attributes, prediction.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]
      new_team = create(:team_season, season:)
      if baseline == :efficiency
        create(:team_offseason_profile, team_season: new_team, manual_adjustment: 3, recruiting_score: nil, returning_minutes_pct: nil)
      else
        previous = create(:season, year: season.year - 1, average_pace: 69.5, average_efficiency: 105.5,
                                   avg_adj_offensive_efficiency: 105.5, avg_adj_defensive_efficiency: 105.5)
        create(:team_season, season: previous, team: new_team.team,
                             adj_offensive_efficiency: 105.5, adj_defensive_efficiency: 105.5, adj_pace: 80.5)
      end
      expect { initializer.call }.to raise_error(ArgumentError, /Saved predictions/)
      expect([season.reload.attributes, prediction.reload.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]).to eq(original)
      expect(new_team.reload.adj_pace).to be_nil
      expect(PreseasonPrior.count).to eq(2)
    end
  end

  it 'rejects publication after live values change without modifying existing outputs' do
    initializer.call
    home.update!(adj_offensive_efficiency: 120)
    before_snapshots = TeamRatingSnapshot.order(:id).map(&:attributes)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    expect(home.reload.adj_offensive_efficiency).to eq(120)
    expect(TeamRatingSnapshot.order(:id).map(&:attributes)).to eq(before_snapshots)
  end

  it 'rejects publication after finalized games or later snapshots exist' do
    initializer.call
    ProphetRatings::TeamRatingSnapshotService.new(season:, as_of: season.start_date).call
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    season.team_rating_snapshots.where(snapshot_date: season.start_date).destroy_all
    create(:game, season:, status: :final)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
  end

  it 'refuses preseason publication for an inactive season with an unmatched completed result' do
    create(:game, season:, status: :final_unmatched)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  describe 'publication guard evaluation' do
    let(:participation_review) { instance_double(SeasonParticipationReview, validate_publication: nil) }

    before do
      allow(SeasonParticipationReview).to receive(:new).with(season).and_return(participation_review)
    end

    it 'validates participation and dates before checking whether the season is current' do
      allow(participation_review).to receive(:validate_publication).and_raise(ArgumentError, 'invalid review')
      allow(season).to receive(:current?).and_return(true)

      expect { initializer.send(:validate_publication) }.to raise_error(ArgumentError, 'invalid review')
      expect(season).not_to have_received(:current?)
    end

    it 'keeps the in-season refusal message and stops before later relations for a current season' do
      allow(season).to receive_messages(games: nil, team_rating_snapshots: nil, rating_team_seasons: nil)
      allow(season).to receive(:current?).and_return(true)

      expect { initializer.send(:validate_publication) }.to raise_error(
        ArgumentError,
        'Existing in-season outputs must be preserved; use an explicitly scoped season:rebuild_ratings.'
      )
      expect(season).not_to have_received(:games)
      expect(season).not_to have_received(:team_rating_snapshots)
      expect(season).not_to have_received(:rating_team_seasons)
    end

    it 'stops after finalized games and does not query snapshots or scan team seasons' do
      completed_relation = double
      games = double(completed: completed_relation)
      allow(season).to receive_messages(current?: false, games:, team_rating_snapshots: nil, rating_team_seasons: nil)
      allow(completed_relation).to receive(:exists?).and_return(true)

      expect { initializer.send(:validate_publication) }.to raise_error(ArgumentError, /season:rebuild_ratings/)
      expect(games).to have_received(:completed).once
      expect(completed_relation).to have_received(:exists?).once
      expect(season).not_to have_received(:team_rating_snapshots)
      expect(season).not_to have_received(:rating_team_seasons)
    end

    it 'refuses a snapshot on another date before scanning team seasons' do
      completed_relation = double
      games = double(completed: completed_relation)
      snapshot_scope = double(exists?: true)
      snapshot_date_relation = double(not: snapshot_scope)
      snapshots = double(where: snapshot_date_relation)
      allow(season).to receive_messages(current?: false, games:, team_rating_snapshots: snapshots, rating_team_seasons: nil)
      allow(completed_relation).to receive(:exists?).and_return(false)

      expect { initializer.send(:validate_publication) }.to raise_error(ArgumentError, /season:rebuild_ratings/)
      expect(season).not_to have_received(:rating_team_seasons)
    end

    it 'checks finalized games before reaching the snapshot relation' do
      completed_relation = double
      games = double(completed: completed_relation)
      snapshots = double(where: double(not: double(exists?: false)))
      allow(season).to receive_messages(current?: false, games:, team_rating_snapshots: snapshots,
                                        rating_team_seasons: [home, away])
      allow(completed_relation).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:changed_ratings?).and_return(false)

      initializer.send(:validate_publication)

      expect(games).to have_received(:completed).once
      expect(completed_relation).to have_received(:exists?).once
      expect(snapshots).to have_received(:where).with(no_args).once
    end

    it 'excludes only the publication date when checking existing snapshots' do
      completed_relation = double
      games = double(completed: completed_relation)
      snapshot_scope = double(exists?: false)
      snapshot_date_relation = double(not: snapshot_scope)
      snapshots = double(where: snapshot_date_relation)
      allow(season).to receive_messages(current?: false, games:, team_rating_snapshots: snapshots,
                                        rating_team_seasons: [home, away])
      allow(completed_relation).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:changed_ratings?).and_return(false)

      initializer.send(:validate_publication)

      expect(snapshot_date_relation).to have_received(:not).with(snapshot_date: season.start_date - 1.day).once
      expect(snapshot_scope).to have_received(:exists?).once
    end

    it 'scans team seasons once only after earlier checks pass and stops at the first changed row' do
      rows = [home, away]
      allow(season).to receive_messages(current?: false, rating_team_seasons: rows)
      allow(season).to receive_messages(games: double(completed: double(exists?: false)),
                                        team_rating_snapshots: double(where: double(not: double(exists?: false))))
      allow(described_class).to receive(:changed_ratings?).with(home).and_return(true)
      allow(described_class).to receive(:changed_ratings?).with(away).and_return(false)

      expect { initializer.send(:validate_publication) }.to raise_error(ArgumentError, /season:rebuild_ratings/)
      expect(season).to have_received(:rating_team_seasons).once
      expect(described_class).to have_received(:changed_ratings?).with(home).once
      expect(described_class).not_to have_received(:changed_ratings?).with(away)
    end

    it 'allows an unchanged inactive season after the publication checks pass' do
      completed_relation = double
      games = double(completed: completed_relation)
      snapshot_scope = double(exists?: false)
      snapshot_date_relation = double(not: snapshot_scope)
      snapshots = double(where: snapshot_date_relation)
      rows = [home, away]
      allow(season).to receive_messages(current?: false, games:, team_rating_snapshots: snapshots, rating_team_seasons: rows)
      allow(completed_relation).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:changed_ratings?).and_return(false)

      expect { initializer.send(:validate_publication) }.not_to raise_error
    end

    it 'scans each team season once after earlier checks pass' do
      completed_relation = double
      games = double(completed: completed_relation)
      snapshots = double(where: double(not: double(exists?: false)))
      rows = [home, away]
      allow(season).to receive_messages(current?: false, games:, team_rating_snapshots: snapshots, rating_team_seasons: rows)
      allow(completed_relation).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:changed_ratings?).and_return(false)

      initializer.send(:validate_publication)

      expect(season).to have_received(:rating_team_seasons).once
      expect(described_class).to have_received(:changed_ratings?).with(home).once
      expect(described_class).to have_received(:changed_ratings?).with(away).once
    end

    it 'checks each core rating while preserving equality, nil and non-core behavior' do
      %w[adj_offensive_efficiency adj_defensive_efficiency adj_pace].each do |stat|
        changed = { stat => 110.0, "preseason_#{stat}" => 100.0 }
        expect(described_class.changed_ratings?(double(attributes: changed))).to be(true)

        equal = { stat => 100.0, "preseason_#{stat}" => 100.0 }
        expect(described_class.changed_ratings?(double(attributes: equal))).to be(false)

        nil_live = { stat => nil, "preseason_#{stat}" => 100.0 }
        expect(described_class.changed_ratings?(double(attributes: nil_live))).to be(false)

        nil_preseason = { stat => 100.0, "preseason_#{stat}" => nil }
        expect(described_class.changed_ratings?(double(attributes: nil_preseason))).to be(true)
      end

      expect(described_class.changed_ratings?(double(attributes: { 'adj_effective_fg_percentage' => 0.5 }))).to be(false)
    end
  end
end
