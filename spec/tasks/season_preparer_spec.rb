# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe SeasonPreparer do
  before { RatingsConfigVersion.publish! }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/season_bootstrap.rake')
    %w[YEAR START_DATE END_DATE SYNC_GAMES DEDUPE_GAMES RUN_PRESEASON RUN_RATINGS RATINGS_RESUME REBUILD
       RATINGS_START_DATE RATINGS_END_DATE ALIGN_CONFERENCES MODEL_VERSION PREVIEW].each { |key| ENV.delete(key) }
    ENV['YEAR'] = '2027'
    ENV['ALIGN_CONFERENCES'] = 'false'
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  def invoke(task)
    Rake::Task[task].reenable
    Rake::Task[task].invoke
  end

  it 'preserves live ratings, snapshots, predictions and current season on repeated bootstrap' do
    season = create(:season, :current, year: 2027)
    team_season = create(:team_season, season:, adj_offensive_efficiency: 119, adj_defensive_efficiency: 99, adj_pace: 72)
    snapshot = create(:team_rating_snapshot, season:, team_season:, team: team_season.team)
    prediction = create(:prediction, game: create(:game, season:), home_team_snapshot: snapshot,
                                     away_team_snapshot: snapshot, ratings_config_version: snapshot.ratings_config_version)
    expect { 2.times { invoke('season:bootstrap') } }.to output(/Season bootstrap complete/).to_stdout
    expect(team_season.reload.adj_offensive_efficiency).to eq(119)
    expect(TeamRatingSnapshot.exists?(snapshot.id)).to be(true)
    expect(Prediction.exists?(prediction.id)).to be(true)
    expect(Season.current).to eq(season)
  end

  it 'requires an explicit valid YEAR before preparing rows' do
    [nil, '2027oops', '0', '2027.5'].each do |year|
      ENV['YEAR'] = year
      expect { invoke('season:prepare') }.to raise_error(SystemExit)
    end
    expect(Season.count).to eq(0)
  end

  it 'rejects former destructive bootstrap flags before any writes' do
    ENV['RUN_RATINGS'] = 'true'
    expect { invoke('season:bootstrap') }.to raise_error(SystemExit)
    expect(Season.count).to eq(0)
  end

  it 'initializes a fresh season transactionally without activating it and permits a safe repeat' do
    create(:team)
    expect { invoke('season:prepare') }.to output(/Season prepared/).to_stdout
    expect { invoke('season:initialize_preseason') }.to output(/Preseason values initialized/).to_stdout
    expect(Season.current).to be_nil
    before_values = TeamSeason.first.attributes.except('updated_at')
    expect { invoke('season:initialize_preseason') }.to output(/Preseason values initialized/).to_stdout
    expect(TeamSeason.first.attributes.except('updated_at')).to eq(before_values)
  end

  it 'previews initializer coverage without publishing priors, live outputs or snapshots' do
    row = create(:team_season, season: create(:season, year: 2027))
    ENV['PREVIEW'] = 'true'
    expect { invoke('season:initialize_preseason') }.to output(/outputs_after.*Preseason values previewed/m).to_stdout
    expect([PreseasonPrior.count, TeamRatingSnapshot.count, row.reload.adj_pace]).to eq([0, 0, nil])
    expect(Season.current).to be_nil
  end

  it 'rehearses no-schedule preparation with reviewed dates and preserves initialized outputs on rerun' do
    create(:team)
    ENV['START_DATE'] = '2026-11-02'
    ENV['END_DATE'] = '2027-04-06'
    expect do
      invoke('season:prepare')
      invoke('season:initialize_preseason')
    end.to output(/Season prepared.*Preseason values initialized/m).to_stdout
    season = Season.find_by!(year: 2027)
    values = season.team_seasons.first.attributes
    ENV.delete('START_DATE')
    ENV.delete('END_DATE')

    expect { 2.times { invoke('season:prepare') } }.to output(/TeamSeasons created: 0/).to_stdout
    expect(season.reload).to have_attributes(start_date: Date.new(2026, 11, 2), end_date: Date.new(2027, 4, 6),
                                             current: false, games: [])
    expect(season.team_seasons.first.attributes).to eq(values)
    expect(season.team_rating_snapshots.pluck(:snapshot_date)).to eq([Date.new(2026, 11, 1)])
  end

  it 'rolls back partial initialization and leaves the old current season unchanged' do
    old_season = create(:season, :current, year: 2026)
    team_season = create(:team_season, season: create(:season, year: 2027))
    initializer = instance_double(ProphetRatings::PreseasonInitializer)
    allow(ProphetRatings::PreseasonInitializer).to receive(:new).and_return(initializer)
    allow(initializer).to receive(:call) do
      team_season.update!(adj_offensive_efficiency: 120)
      raise 'failed initialization'
    end
    expect { invoke('season:initialize_preseason') }.to raise_error('failed initialization')
    expect(team_season.reload.adj_offensive_efficiency).to be_nil
    expect(Season.current).to eq(old_season)
  end

  it 'activates only on the explicit activation task' do
    create(:team)
    expect { invoke('season:prepare') }.to output(/Season prepared/).to_stdout
    expect { invoke('season:initialize_preseason') }.to output(/Preseason values initialized/).to_stdout
    expect { invoke('season:activate') }.to output(/Season activated/).to_stdout
    expect(Season.current.year).to eq(2027)
  end

  it 'requires explicit confirmation and dates before a destructive rebuild' do
    create(:season, year: 2027)
    expect { invoke('season:rebuild_ratings') }.to raise_error(SystemExit)
    ENV['REBUILD'] = 'true'
    expect { invoke('season:rebuild_ratings') }.to raise_error(SystemExit)
  end

  it 'reports a synchronous resume failure instead of silently scheduling a retry' do
    season = create(:season, year: 2027)
    allow(Game).to receive(:current_schedule_date).and_return(season.start_date)
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    allow(calculator).to receive(:call).and_raise('failed ratings')
    expect { invoke('season:resume_ratings') }.to raise_error('failed ratings')
  end
end
