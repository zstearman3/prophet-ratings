# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe Importer::Setup::BaseDataImporter do
  let(:seed_paths) { {} }

  around do |example|
    Tempfile.create(['teams', '.csv']) do |teams|
      Tempfile.create(['conferences', '.csv']) do |conferences|
        teams.write("school,nickname,url,location,slug,primary_color,short_name,home_venue,secondary_name\n" \
                    "Alpha,Testers,alpha,Testville,alpha,#123456,ALP,Alpha Arena,Alpha College\n")
        conferences.write("name,abbreviation,slug\nTest Conference,TC,test\n")
        teams.flush
        conferences.flush
        seed_paths[:teams] = teams.path
        seed_paths[:conferences] = conferences.path
        example.run
      end
    end
  end

  before do
    allow(Rails.root).to receive(:join).and_call_original
    allow(Rails.root).to receive(:join).with('db/seeds/scraped_teams.csv').and_return(seed_paths[:teams])
    allow(Rails.root).to receive(:join).with('db/seeds/conferences.csv').and_return(seed_paths[:conferences])
  end

  it 'creates an inactive historical shell and persisted alias, with no changes on identical reruns' do
    described_class.run
    team = Team.find_by!(school: 'Alpha')
    season = Season.find_by!(year: 2025)
    expect(season).to have_attributes(name: '2024-25', current: false,
                                      start_date: Date.new(2024, 11, 1), end_date: Date.new(2025, 4, 10))
    expect(TeamAlias.find_by!(value: 'Alpha College')).to have_attributes(team:, source: 'sports-reference')
    before = [Team, TeamAlias, Season, TeamSeason, Conference].map { |model| model.order(:id).map(&:attributes) }

    2.times { described_class.run }

    expect([Team, TeamAlias, Season, TeamSeason, Conference].map { |model| model.order(:id).map(&:attributes) }).to eq(before)
    expect(TeamConference.count).to eq(0)
  end

  [2025, 2027].each do |current_year|
    it "preserves existing season and model state when #{current_year} is current" do
      historical = create(:season, year: 2025, current: current_year == 2025,
                                   name: 'Reviewed', start_date: Date.new(2024, 11, 4),
                                   average_efficiency: 111, average_pace: 73)
      current = current_year == 2025 ? historical : create(:season, :current, year: current_year)
      team_season = create(:team_season, season: historical, adj_offensive_efficiency: 120)
      snapshot = create(:team_rating_snapshot, season: historical, team_season:, team: team_season.team)
      prediction = create(:prediction, game: create(:game, season: historical), home_team_snapshot: snapshot,
                                       away_team_snapshot: snapshot, ratings_config_version: snapshot.ratings_config_version)
      before = [historical, current, team_season, snapshot, prediction].map(&:attributes)

      2.times { described_class.run }

      expect([historical, current, team_season, snapshot, prediction].map { |record| record.reload.attributes }).to eq(before)
      expect(Season.current).to eq(current)
    end
  end

  it 'rejects an alias already owned by another team and rolls back the base import' do
    other = create(:team)
    create(:team_alias, team: other, value: 'Alpha College', source: 'sports-reference')
    expect { described_class.run }.to raise_error(ArgumentError, /alias "Alpha College" conflicts with another team/)
    expect(Team.find_by(school: 'Alpha')).to be_nil
    expect(Season.count).to eq(0)
    expect(TeamAlias.find_by!(value: 'Alpha College').team).to eq(other)
  end

  it 'runs only base import from db:seed and preserves existing memberships' do
    membership = create(:team_conference)
    before = membership.attributes
    allow(Importer::Setup::TeamConferencesSynchronizer).to receive(:new).and_call_original
    allow(SeasonPreparer).to receive(:new).and_call_original

    load Rails.root.join('db/seeds.rb')

    expect(membership.reload.attributes).to eq(before)
    expect(Importer::Setup::TeamConferencesSynchronizer).not_to have_received(:new)
    expect(SeasonPreparer).not_to have_received(:new)
  end
end
