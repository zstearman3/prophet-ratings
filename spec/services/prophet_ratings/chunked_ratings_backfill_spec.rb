# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::ChunkedRatingsBackfill do
  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2025, 11, 5)) }
  let(:version) { create(:ratings_config_version) }
  let!(:teams) { create_list(:team_season, 2, season:) }
  let(:request) { { 'year' => season.year, 'model' => version.name, 'initialize_preseason' => true } }
  let(:output) { StringIO.new }

  def service(values = request)
    described_class.new(values, output:)
  end

  def initialize_priors
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
  end

  def publish_day(date, rows = teams)
    rows.each do |row|
      create(:team_rating_snapshot, team_season: row, ratings_config_version: version, snapshot_date: date)
    end
  end

  def run_request(plan, first: plan.fetch('next_date'), last: plan.fetch('through'))
    plan.merge('from' => first, 'through' => last)
  end

  it 'plans a new model without changing ratings, captures, snapshots or activation' do
    old = create(:ratings_config_version, current: true)
    plan = service.plan
    expect(plan).to include('next_date' => '2025-11-01', 'completed_days' => 0, 'total_days' => 5,
                            'model_id' => version.id, 'initialize_preseason' => true)
    expect(PreseasonPrior.count).to eq(0)
    expect(TeamRatingSnapshot.count).to eq(0)
    expect(RatingsConfigVersion.current).to eq(old)
  end

  it 'requires explicit initialization and refuses to initialize over existing model outputs' do
    expect { service(request.except('initialize_preseason')).plan }.to raise_error(ArgumentError, /initialize-preseason/)
    publish_day(season.start_date)
    expect { service.plan }.to raise_error(ArgumentError, /existing model outputs/)
    expect(TeamRatingSnapshot.count).to eq(2)
  end

  it 'finds the earliest coverage hole rather than skipping ahead to a later snapshot' do
    initialize_priors
    publish_day(season.start_date)
    publish_day(season.start_date + 1, teams.first(1))
    publish_day(season.end_date)
    expect(service.plan).to include('next_date' => '2025-11-02', 'completed_days' => 1, 'initialize_preseason' => false)
  end

  it 'reports a complete window without replaying or resetting it' do
    initialize_priors
    (season.start_date..season.end_date).each { |date| publish_day(date) }
    expect(service.plan).to include('next_date' => nil, 'completed_days' => 5, 'initialize_preseason' => false)
  end

  it 'rejects old checkpoints after a reviewed participant cohort shrinks' do
    initialize_priors
    (season.start_date..season.end_date).each { |date| publish_day(date) }
    create(:team_alias, team: teams.first.team, value: teams.first.team.school)
    season.update!(participation_review: {
                     'evidence' => 'Synthetic roster', 'reviewed_by' => 'Test operator',
                     'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601,
                                  'evidence' => 'Synthetic schedule' },
                     'teams' => teams.each_with_index.map do |team, index|
                       { 'team_id' => team.team_id, 'status' => (index.zero? ? 'included' : 'excluded'), 'reason' => 'Synthetic review' }
                     end,
                     'unresolved_identities' => []
                   })
    expect { service.plan }.to raise_error(ArgumentError, /checkpoint participation/)
    expect(season.team_rating_snapshots.count).to eq(12)
  end

  it 'pins the model and prints committed daily progress while using unchanged prior arithmetic' do
    plan = service.plan
    other = create(:ratings_config_version, current: true)
    service(run_request(plan, last: season.start_date.iso8601)).run
    snapshots = season.team_rating_snapshots.where(snapshot_date: season.start_date)
    expect(snapshots.pluck(:ratings_config_version_id, :adj_offensive_efficiency)).to eq([[version.id, 105.5], [version.id, 105.5]])
    expect(PreseasonPrior.where(ratings_config_version: version).count).to eq(2)
    expect(RatingsConfigVersion.current).to eq(other)
    expect(output.string).to include('date=2025-11-01', 'status=starting', 'status=committed', 'elapsed=')
  end

  it 'keeps completed days after a later failure and resumes without replacing captured priors' do
    plan = service.plan
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_wrap_original do |method, **arguments|
      raise 'synthetic publication failure' if arguments[:as_of] == season.start_date + 1

      method.call(**arguments)
    end
    expect { service(run_request(plan)).run }.to raise_error('synthetic publication failure')
    prior_ids = PreseasonPrior.where(ratings_config_version: version).ids
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date).count).to eq(2)
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date + 1).count).to eq(0)
    expect(service.plan).to include('next_date' => '2025-11-02', 'initialize_preseason' => false)
    expect(PreseasonPrior.where(ratings_config_version: version).ids).to eq(prior_ids)
  end

  it 'rejects participant changes between planning and execution before initializing anything' do
    plan = service.plan
    create(:team_season, season:)
    expect { service(run_request(plan)).run }.to raise_error(ArgumentError, /selection changed/)
    expect(PreseasonPrior.count).to eq(0)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'rejects missing earlier checkpoint coverage rather than silently skipping a deleted date' do
    initialize_priors
    publish_day(season.start_date)
    plan = service.plan
    season.team_rating_snapshots.where(snapshot_date: season.start_date).destroy_all
    expect { service(run_request(plan)).run }.to raise_error(ArgumentError, /[Ee]arlier dates.*incomplete/)
  end

  it 'rejects invalid, out-of-season and future boundaries, and late initialization' do
    bad_ranges = [{ 'from' => '2025-11-04', 'through' => '2025-11-02' }, { 'from' => '2025-10-31' },
                  { 'through' => '2025-11-05T00:00:00Z' }]
    bad_ranges.each do |bounds|
      expect { service(request.merge(bounds)).plan }.to raise_error(ArgumentError)
    end
    allow(Game).to receive(:current_schedule_date).and_return(season.start_date + 1)
    expect { service(request.merge('through' => '2025-11-05')).plan }.to raise_error(ArgumentError, /date range/)
    expect { service(request.merge('from' => '2025-11-02')).plan }.to raise_error(ArgumentError, /season opening/)
  end
end
