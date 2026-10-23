# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonReadinessActivation do
  include ReadinessFixture

  let(:season) { create(:season) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:admin) { create(:user, :admin) }
  let(:row) { create(:team_season, season:) }
  let(:review) { save_readiness_review(season, admin, deferrals: { 'schedule' => 'Schedule not yet published.' }) }

  before do
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
    publish_readiness_fixture(season, model, row, admin)
  end

  def activate(action, record = review)
    described_class.new(record, actor: admin, action:).call
  end

  it 'requires acknowledgement and rejects forged or hard deferrals' do
    report = OffseasonReadiness.new(season).call
    args = { reviewer: admin, fingerprint: report['fingerprint'] }
    expect { OffseasonReadinessReview.record!(season, **args, acknowledge: '0') }.to raise_error(ArgumentError, /acknowledge/)
    expect { save_readiness_review(season, admin, deferrals: { 'publication' => 'Skip' }) }.to raise_error(ArgumentError, /optional/)
    expect { save_readiness_review(season, admin, deferrals: { 'forged' => 'Skip' }) }.to raise_error(ArgumentError, /optional/)
    expect(review.reload.deferrals).to eq('schedule' => 'Schedule not yet published.')
    expect(review.acknowledgement['gaps']).to eq(review.report['gaps'])
  end

  it 'activates season separately, retains decisions and requires refreshed review for the model switch' do
    default = RatingsConfigVersion.published_default
    result = activate('season')
    expect([season.reload.current?, RatingsConfigVersion.published_default]).to eq([true, default])
    expect(result['status']).to eq('succeeded')
    expect { activate('model') }.to raise_error(ArgumentError, /stale/)
    fresh = save_readiness_review(season, admin)
    expect(activate('model', fresh)['resulting']['model_id']).to eq(model.id)
    expect(review.reload.deferrals['schedule']).to be_present
  end

  it 'replays recorded success without switching back after another operator changes current season' do
    first = activate('season')
    other = create(:season, year: 2030)
    season.reload.update!(current: false)
    other.update!(current: true)
    expect(activate('season')).to eq(first)
    expect(Season.current).to eq(other)
  end

  %i[alias dates profile model_roundtrip].each do |change|
    it "rejects stale #{change} and retains failure without switching" do
      review
      case change
      when :alias then row.team.team_aliases.first.update!(value: 'Changed alias')
      when :dates then season.update!(end_date: season.end_date + 1)
      when :profile then create(:team_offseason_profile, team_season: row, manual_adjustment: 2)
      when :model_roundtrip
        other = create(:ratings_config_version)
        PreseasonPublication.select_model(season, other)
        PreseasonPublication.select_model(season, model)
      end
      expect { activate('season') }.to raise_error(ArgumentError, /stale/)
      expect(season.reload).not_to be_current
      expect(review.reload.attempts.last['status']).to eq('failed')
      expect(review.results).to be_empty
    end
  end

  %w[season model].each do |action|
    it "rolls back #{action} activation if success result persistence fails, retaining the failed attempt" do
      review
      original = [Season.current&.id, RatingsConfigVersion.published_default&.id]
      allow(review).to receive(:update!).and_call_original
      allow(review).to receive(:update!).with(hash_including(:results)).and_raise('result unavailable')
      expect { activate(action) }.to raise_error(RuntimeError, 'result unavailable')
      expect([Season.current&.id, RatingsConfigVersion.published_default&.id]).to eq(original)
      expect(review.reload.results).to be_empty
      expect(review.attempts.last['error']).to include('result unavailable')
    end
  end

  it 'retains lock contention failure without switch or enqueue' do
    review
    allow(Season).to receive(:with_ratings_lock).and_raise(Season::OperationInProgress, 'Writer busy')
    expect { activate('season') }.to raise_error(Season::OperationInProgress)
    expect(season.reload).not_to be_current
    expect(review.reload.attempts.last['error']).to include('Writer busy')
  end

  it 'preserves explicitly serialized queued season/model targets through both switches' do
    old = create(:season, year: 2030, current: true)
    original = create(:ratings_config_version)
    original.activate
    jobs = [UpdateRankingsJob, GenerateNightlyPredictionsJob].map { |type| type.new(old.id) }
    jobs.each { |job| job.send(:pin_model_version) }
    payloads = jobs.map(&:serialize)
    activate('season')
    activate('model', save_readiness_review(season, admin))
    restored = payloads.map do |payload|
      job = ActiveJob::Base.deserialize(payload)
      job.send(:deserialize_arguments_if_needed)
      job.arguments
    end
    expect(restored.map(&:first)).to eq([old.id, old.id])
    expect(restored.map { |args| args.last[:ratings_config_version_id] }).to eq([original.id, original.id])
    expect(PublishPreseasonJob).to have_received(:perform_later).once
  end

  it 'records a repeated default target as an explicit no-op without calculation or source alignment' do
    model.activate
    allow(ProphetRatings::PreseasonInitializer).to receive(:new).and_raise('Unexpected calculation')
    allow(SeasonConferenceAlignment).to receive(:new).and_raise('Unexpected source alignment')
    result = activate('model')
    expect(result['status']).to eq('no_op')
    expect(result['actor_id']).to eq(admin.id)
    expect(review.reload.results.fetch('model')).to eq(result)
  end

  it 'allows an open review but never lets missing core data authorize either switch' do
    row.reload.update!(adj_pace: nil)
    record = save_readiness_review(season, admin)
    expect { activate('season', record) }.to raise_error(ArgumentError, /required readiness/)
    expect { activate('model', record) }.to raise_error(ArgumentError, /required readiness/)
    expect([Season.current, RatingsConfigVersion.current]).to eq([nil, nil])
  end

  def independent_ratings_lock_available?
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    connection = PG.connect(config.slice(:host, :port, :password).merge(dbname: config[:database], user: config[:username],
                                                                        connect_timeout: 2, options: '-c statement_timeout=2000'))
    key_sql = GoodJob::Job.advisory_lock_bigint_sql('$1::text')
    connection.exec_params("SELECT pg_try_advisory_lock(#{key_sql})", [Season::RATINGS_LOCK_KEY]).getvalue(0, 0) == 't'
  ensure
    connection&.close
  end

  it 'holds the real shared ratings writer lock during the final guarded validation' do
    observed = []
    allow(review).to receive(:verify_current).and_wrap_original do |original|
      observed << independent_ratings_lock_available?
      original.call
    end
    activate('season')
    expect(observed).to eq([false])
    expect(season.reload).to be_current
  end

  it 'rejects a changed effective default before action without replacing that default' do
    review
    other = create(:ratings_config_version)
    other.activate
    expect { activate('model') }.to raise_error(ArgumentError, /stale/)
    expect(RatingsConfigVersion.current).to eq(other)
    expect(review.reload.attempts.last['actual']['model_id']).to eq(other.id)
  end
end
