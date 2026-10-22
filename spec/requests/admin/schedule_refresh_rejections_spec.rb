# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Schedule refresh rejected evidence' do
  include Devise::Test::IntegrationHelpers

  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:admin) { create(:user, :admin) }
  let(:home) { create(:team, school: 'Known school') }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: admin, provider: 'sports_reference', start_date: today.to_s, end_date: today.to_s)
  end
  let(:names) { ['Unknown visitor <script>first</script>', 'Unknown visitor second CBBD_API_KEY=sensitive'] }
  let(:rows) do
    names.map do |name|
      { date: today, home_team: home.school, away_team: name, source_status: 'scheduled', source_completed: false,
        url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?day=1' }
    end
  end

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    create(:team_season, team: home, season:)
    scraper = instance_double(Scraper::GamesScraper, game_count: 2, to_json_in_batches: rows)
    allow(Scraper::GamesScraper).to receive(:new).and_return(scraper)
    enrichment = instance_double(Scraper::TeamScheduleEnrichmentScraper, schedule_data: [])
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).and_return(enrichment)
    allow(Ingestion::FutureScheduleRefresh).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |refresh| allow(refresh).to receive(:sleep) }
    end
    sign_in admin
  end

  it 'links only retained rejection observations matching the run provider, season and requested dates' do
    records = [['sports_reference', season.year, today], ['cbbd', season.year, today],
               ['sports_reference', 2028, today], ['sports_reference', season.year, today + 1.day]].map do |provider, year, date|
      GameObservation.create!(provider:, outcome: 'unmatched', normalized_payload: { season_year: year, schedule_date: date.to_s })
    end
    run.update!(report: { days: [{ date: today.to_s, error: 'Failed', rejection_observation_ids: records.map(&:id) }] })
    get admin_schedule_refresh_run_path(run)
    links = response.parsed_body.css('a').pluck('href')
    expect(links).to include("/admin/game_observation/#{records.first.id}")
    expect(links & records.drop(1).map { |record| "/admin/game_observation/#{record.id}" }).to be_empty
  end

  shared_examples 'actionable durable rejections' do |outcome|
    it "links two distinct #{outcome} source rows to scoped retained evidence after real canonical rollback" do
      Ingestion::ScheduleRefreshExecution.new(run).call
      day = run.reload.report.fetch('days').first
      ids = day.fetch('rejection_observation_ids', [])
      expect(ids.size).to eq(2)
      expect(Game.count).to eq(0)
      observations = GameObservation.where(id: ids).order(:id)
      expect(observations.pluck(:outcome)).to eq([outcome, outcome])
      expect(observations.map { |record| record.normalized_payload.dig('away', 'name') }).to eq(names)
      get admin_schedule_refresh_run_path(run)
      aggregate_failures do
        ids.each do |id|
          expect(response.parsed_body.at_css("a[href='/admin/game_observation/#{id}']")).to be_present
        end
        expect(response.body).not_to include('<script>first</script>', 'CBBD_API_KEY=sensitive')
        expect(response.body).to include(admin_schedule_refresh_runs_path(season_id: season.id))
      end
      return_path = admin_schedule_refresh_runs_path(season_id: season.id)
      get "/admin/game_observation/#{ids.first}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Unknown visitor', return_path)
      expect(response.body).not_to include('<script>first</script>')
    end
  end

  it_behaves_like 'actionable durable rejections', 'unmatched'

  context 'when both source labels resolve ambiguously' do
    before do
      names.each do |name|
        first = create(:team)
        second = create(:team)
        create(:team_alias, team: first, value: name, source: 'synthetic')
        create(:team_alias, team: second, value: name, source: 'other-synthetic')
      end
    end

    it_behaves_like 'actionable durable rejections', 'ambiguous'
  end
end
