# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRatingsCalculator do
  include ActiveSupport::Testing::TimeHelpers

  let(:payload) do
    RatingsConfigVersion.authored_config.merge(bundle_name: 'coaching-test').tap do |config|
      config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
    end
  end
  let(:version) { RatingsConfigVersion.publish!(payload) }
  let(:season) { create(:season, year: 2027, start_date: Date.new(2026, 11, 1), end_date: Date.new(2027, 4, 10)) }
  let(:previous) do
    create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10), average_pace: 69)
  end
  let(:destination) { create(:team) }
  let(:source) { create(:team) }
  let(:home) { create(:team_season, season:, team: destination) }
  let(:away) { create(:team_season, season:) }
  let(:move) do
    CoachingChange.create!(team: destination, previous_team: source, effective_year: 2027, previous_year: 2026,
                           coach_name: 'Synthetic Coach', previous_role: 'head_coach', full_season_head_coach: true,
                           previous_season_d1: true, status: 'confirmed')
  end
  let(:calculator) { described_class.new(season, ratings_config_version: version) }
  let(:revision) { ProphetRatings::PreseasonRevision.new(season, ratings_config_version: version) }

  def ready
    CoachingReview.find_or_initialize_by(year: 2027).update!(ready: true)
  end

  def history
    create(:team_season, season: previous, team: destination, adj_pace: 68)
    create(:team_season, season: previous, team: source, adj_pace: 74)
  end

  def capture
    calculator.call
    home.reload.preseason_prior
  end

  def scheduled_forecast(selected)
    game = create(:game, season:, status: :scheduled, start_time: season.start_date.in_time_zone + 12.hours)
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
    ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: selected).call
  end

  it 'resolves stored history by Team/year after moves entered before Season preparation' do
    move
    expect(Season.count).to eq(0)
    history
    home
    ready
    prior = capture
    # 0.15*69 + 0.85*68 = 68.15; signal 69 + (74-69) = 74; 50/50 blend gives 71.075.
    expect(prior.outputs.fetch('preseason_adj_pace')).to eq(71.075)
    expect(prior.inputs.fetch('coaching')).to include('reason' => 'eligible', 'target_anchor' => 69,
                                                      'source_baseline' => 69, 'source_adjusted_pace' => 74,
                                                      'source_season_id' => previous.id, 'source_team_id' => source.id)
    expect(prior.inputs.dig('coaching', 'moves', 0)).to include('id' => move.id, 'previous_season_d1' => true)
    expect(prior.inputs.fetch('contract')).to eq('preseason-v2-coaching')
  end

  it 'requires readiness on direct preview/capture and revision boundaries, with no partial writes' do
    home
    expect { calculator.preview_inputs(home) }.to raise_error(ArgumentError, /not ready/)
    expect { calculator.call }.to raise_error(ArgumentError, /not ready/)
    expect { revision.preview }.to raise_error(ArgumentError, /not ready/)
    expect { revision.call(preview_key: 'anything') }.to raise_error(ArgumentError, /not ready/)
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'accepts an explicitly ready empty year and rejects pending candidates even with stale readiness' do
    home
    ready
    expect(calculator.preview_inputs(home)[:coaching][:reason]).to eq('no_confirmed_move')
    CoachingChange.create!(effective_year: 2027)
    CoachingReview.where(year: 2027).update_all(ready: true) # rubocop:disable Rails/SkipsModelValidations
    expect { calculator.preview_inputs(home) }.to raise_error(ArgumentError, /pending/)
    expect(PreseasonPrior.count).to eq(0)
  end

  [[:previous_role, 'assistant', 'unsupported_role'], [:previous_role, 'interim', 'unsupported_role'],
   [:previous_role, nil, 'unsupported_role'], [:full_season_head_coach, false, 'unconfirmed_full_season'],
   [:previous_season_d1, false, 'unconfirmed_d1'], [:previous_year, 2025, 'stale_history'],
   [:status, 'rejected', 'rejected']].each do |field, value, reason|
    it "retains the prior for #{reason} with explicit coverage" do
      history
      changes = { field => value, reconfirm: true }
      changes[:full_season_head_coach] = false if field == :previous_role
      move.update!(changes)
      home
      ready
      prior = capture
      expect(prior.inputs.dig('coaching', 'reason')).to eq(reason)
      expect(prior.outputs.fetch('preseason_adj_pace')).to eq(68.15)
    end
  end

  it 'records missing Season history without preventing a confirmed move' do
    move
    home
    ready
    prior = capture
    expect(prior.inputs.dig('coaching', 'reason')).to eq('missing_source_season')
    expect(prior.outputs.fetch('preseason_adj_pace')).to eq(69.5)
  end

  it 'excludes missing TeamSeason and unusable stored source pace/baseline' do
    previous
    move
    home
    ready
    expect(calculator.preview_inputs(home)[:coaching][:reason]).to eq('missing_source_team_season')
    row = create(:team_season, season: previous, team: source, adj_pace: nil)
    expect(calculator.preview_inputs(home)[:coaching][:reason]).to eq('invalid_source_pace')
    row.update!(adj_pace: 74)
    previous.update!(average_pace: nil)
    expect(calculator.preview_inputs(home)[:coaching][:reason]).to eq('invalid_source_baseline')
    previous.update!(average_pace: 0)
    expect(calculator.preview_inputs(home)[:coaching][:reason]).to eq('invalid_source_baseline')
  end

  it 'excludes a source season that has not completed' do
    history
    previous.update!(end_date: season.start_date)
    move
    ready
    expect(calculator.preview_inputs(home)[:coaching][:reason]).to eq('incomplete_source_season')
  end

  it 'replays/reuses frozen captures without any mutable coaching, readiness or source lookup' do
    history
    move
    home
    ready
    prior = capture
    move.update!(coach_name: 'Corrected Coach', reconfirm: true)
    previous.team_seasons.find_by!(team: source).update!(adj_pace: 80)
    season.update!(average_pace: 99)
    allow(CoachingChange).to receive(:where).and_raise('mutable coaching read')
    allow(CoachingReview).to receive(:find_by).and_raise('mutable readiness read')
    allow(Season).to receive(:find_by).and_raise('mutable history read')
    calculator.call
    expect(home.reload.preseason_prior_id).to eq(prior.id)
    expect(ProphetRatings::PreseasonPriorFormula.new(prior.inputs, version.config).call).to eq(prior.outputs)
  end

  it 'keeps zero-weight outputs exactly compatible with v1 including profile effects' do
    history
    move
    home
    ready
    create(:team_offseason_profile, team_season: home, manual_adjustment: 2)
    old = RatingsConfigVersion.publish!
    described_class.new(season, ratings_config_version: old).call
    original = home.reload.preseason_prior
    payload[:preseason][:coaching][:weight] = 0
    expect(capture.outputs).to eq(original.outputs)
    expect(original.inputs.fetch('contract')).to eq('preseason-v1')
    expect(original.reload.outputs).to eq(capture.outputs)
  end

  it 'fails clearly for unknown and mismatched contracts and invalid coaching payloads' do
    home
    ready
    inputs = calculator.preview_inputs(home)
    inputs[:contract] = 'unknown'
    expect { ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call }.to raise_error(ArgumentError, /contract/)
    inputs[:contract] = 'preseason-v1'
    expect { ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call }.to raise_error(ArgumentError, /contract/)
    inputs[:contract] = 'preseason-v2-coaching'
    inputs[:coaching] = {}
    expect { ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call }.to raise_error(KeyError)
  end

  it 'rejects malformed or nonpositive new-contract team pace operands instead of coercing them to zero' do
    home
    ready
    inputs = calculator.preview_inputs(home)
    inputs[:previous_values]['adj_pace'] = 'invalid'
    expect { ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call }.to raise_error(ArgumentError, /positive/)
    inputs[:previous_values]['adj_pace'] = nil
    inputs[:baselines]['adj_pace'] = 0
    expect { ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call }.to raise_error(ArgumentError, /positive/)
  end

  it 'rejects stale reviewed facts, publishes atomically and reaches snapshots and a scheduled forecast' do
    history
    move
    home
    away
    old = RatingsConfigVersion.publish!
    travel_to((season.start_date - 1.day).in_time_zone + 12.hours)
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: old).call
    old_forecast = scheduled_forecast(old)
    old_outputs = [PreseasonPrior.where(ratings_config_version: old).map(&:attributes),
                   TeamRatingSnapshot.where(ratings_config_version: old).map(&:attributes), old_forecast.attributes]
    ready
    report = revision.preview
    expect(report[:teams].find { |row| row[:team_id] == home.team_id }[:coaching]).to include(
      signal: 74, weight: 0.5, adjustment: be_within(1e-9).of(2.925), new_pace: 71.075
    )
    move.update!(coach_name: 'Corrected Coach', reconfirm: true)
    ready
    expect { revision.call(preview_key: report[:preview_key]) }.to raise_error(ArgumentError, /rerun.*preview/)
    revision.call(preview_key: revision.preview[:preview_key])
    snapshot = home.team_rating_snapshots.find_by!(ratings_config_version: version)
    expect(snapshot.stats.dig('preseason_prior', 'inputs', 'coaching', 'moves', 0, 'coach_name')).to eq('Corrected Coach')
    forecast = ProphetRatings::GamePredictionBuilder.new(old_forecast.game, ratings_config_version: version).call
    expect(forecast.pace).to eq(70.04)
    expect([PreseasonPrior.where(ratings_config_version: old).map(&:attributes),
            TeamRatingSnapshot.where(ratings_config_version: old).map(&:attributes), old_forecast.reload.attributes]).to eq(old_outputs)
  end

  it 'reuses revision identities, refuses input changes under the same version and rolls back failed publication' do
    history
    move
    home
    away
    ready
    report = revision.preview
    snapshots = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(snapshots)
    allow(snapshots).to receive(:call).and_raise('publication failed')
    expect { revision.call(preview_key: report[:preview_key]) }.to raise_error('publication failed')
    expect([PreseasonPrior.count, TeamRatingSnapshot.count, home.reload.adj_pace]).to eq([0, 0, nil])
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_call_original
    revision.call(preview_key: report[:preview_key])
    ids = [PreseasonPrior.ids, TeamRatingSnapshot.ids]
    revision.call(preview_key: revision.preview[:preview_key])
    expect([PreseasonPrior.ids, TeamRatingSnapshot.ids]).to eq(ids)
    move.update!(coach_name: 'Correction', reconfirm: true)
    ready
    expect { revision.preview }.to raise_error(ArgumentError, /new MODEL_VERSION/)
  end

  it 'publishes the opt-in authored experimental configuration without changing default selection' do
    experiment = Rails.application.config_for(:ratings, env: :coaching_experiment).to_h.deep_symbolize_keys
    selected = RatingsConfigVersion.publish!(RatingsConfigVersion.authored_config.merge(experiment))
    expect(selected.settings.dig(:preseason, :coaching)).to eq(formula: 'relative_pace_v2', weight: 0.5)
    expect(selected.name).to eq('v1.8-experimental-coaching-pace')
    expect(RatingsConfigVersion.current).to be_nil
  end

  it 'tunes weight through a new immutable configuration while preserving the original capture' do
    history
    move
    home
    ready
    original = capture
    tuned = version.config.deep_dup
    tuned['bundle_name'] = 'coaching-tuned'
    tuned['preseason']['coaching']['weight'] = 0.2
    selected = RatingsConfigVersion.publish!(tuned)
    described_class.new(season, ratings_config_version: selected).call
    expect(home.reload.preseason_prior.outputs.fetch('preseason_adj_pace')).to eq(69.32)
    expect(original.reload.outputs.fetch('preseason_adj_pace')).to eq(71.075)
    expect(original.inputs.dig('configuration', 'preseason', 'coaching', 'weight')).to eq(0.5)
    expect(selected.settings.dig(:preseason, :coaching, :weight)).to eq(0.2)
  end

  it 'reports fresh initializer coverage without writes and then reports captured reuse without source reads' do
    history
    move
    home
    ready
    initializer = ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version)
    report = initializer.preview
    expect(report[:teams].first[:coaching]).to include(old_pace: 68.15, signal: 74, new_pace: 71.075)
    expect([PreseasonPrior.count, TeamRatingSnapshot.count, home.reload.adj_pace]).to eq([0, 0, nil])
    initializer.call
    move.update!(coach_name: 'Correction', reconfirm: true)
    allow(CoachingChange).to receive(:where).and_raise('mutable read')
    expect(initializer.preview[:teams].first[:outputs_after]['preseason_adj_pace']).to eq(71.075)
  end

  it 'treats D1 confirmation as a reviewed fact requiring reconfirmation and readiness invalidation' do
    move
    ready
    expect { move.update!(previous_season_d1: false) }.to raise_error(ActiveRecord::RecordInvalid, /reconfirm/)
    move.update!(previous_season_d1: false, reconfirm: true)
    expect(CoachingReview.find_by!(year: 2027)).not_to be_ready
    ready
    expect(move.reload.apply_imported_facts(previous_season_d1: true)).to be(false)
    expect(CoachingReview.find_by!(year: 2027)).to be_ready
  end

  it 'requires resolved previous team/year for D1 assertions without attributing head-coach responsibility to assistants' do
    candidate = CoachingChange.new(team: destination, effective_year: 2027, coach_name: 'Assistant',
                                   previous_season_d1: true, status: 'confirmed')
    expect(candidate).not_to be_valid
    candidate.assign_attributes(previous_team: source, previous_year: 2026, previous_role: 'assistant')
    expect(candidate).to be_valid
    expect(candidate.full_season_head_coach).to be(false)
  end
end
