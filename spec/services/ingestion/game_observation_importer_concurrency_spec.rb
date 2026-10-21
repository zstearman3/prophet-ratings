# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Ingestion::GameObservationImporter do
  self.use_transactional_tests = false

  let(:token) { SecureRandom.hex(6) }
  let(:season) { create(:season, year: 2025, start_date: '2024-11-01', end_date: '2025-04-01') }
  let(:teams) { %w[Home Away].map { |side| create(:team, school: "#{side} #{token}") } }
  let(:first_applied) { Queue.new }
  let(:release_first) { Queue.new }
  let(:second_pid) { Queue.new }
  let(:results) { Queue.new }
  let(:threads) { [] }
  let(:payload) do
    { contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1',
      provider: "first-#{token}", external_game_id: '001', season_year: season.year,
      schedule_date: '2025-01-01', source_status: 'scheduled', source_completed: false,
      captured_at: '2025-01-01T12:00:00Z', adapter_revision: 'synthetic-1', source_url: '/same-game',
      home: { name: teams.first.school, stats: {} }, away: { name: teams.last.school, stats: {} } }
  end

  before do
    teams.each { |team| create(:team_season, team:, season:) }
    payload
  end

  after do
    release_first << true
    threads.each { |thread| thread.join(10) }
    games = Game.where(season_id: season.id)
    GameObservation.where(provider: ["first-#{token}", "second-#{token}"]).delete_all
    GameExternalIdentity.where(game_id: games.select(:id)).delete_all
    games.destroy_all
    season.destroy!
    teams.each(&:destroy!)
  end

  it 'keeps bootstrap locked through the outer commit across separate provider connections' do
    start_first_writer
    Timeout.timeout(10) { first_applied.pop }
    start_second_writer
    wait_for_advisory_waiter(Timeout.timeout(10) { second_pid.pop })
    expect(results.size).to eq(1)
    release_first << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    reports = Array.new(2) { results.pop }
    game_ids = reports.pluck(:game_id).uniq
    aggregate_failures do
      expect(reports.pluck(:outcome)).to eq(%w[scheduled unchanged])
      expect(game_ids.size).to eq(1)
      expect(GameExternalIdentity.where(game_id: game_ids).count).to eq(2)
      expect(TeamGame.where(game_id: game_ids).count).to eq(2)
    end
  end

  it 'serializes a missing-ID projection with stable-ID bootstrap through the outer commit' do
    projection = payload.merge(external_game_id: nil, source_url: '/cbb/boxscores/index.cgi?day=1')
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Game.transaction do
          results << described_class.new(observation: projection, season:).call
          first_applied << true
          release_first.pop
        end
      end
    end
    Timeout.timeout(10) { first_applied.pop }
    start_second_writer(payload)
    wait_for_advisory_waiter(Timeout.timeout(10) { second_pid.pop })
    expect(results.size).to eq(1)
    release_first << true
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
    reports = Array.new(2) { results.pop }
    aggregate_failures do
      expect(reports.pluck(:outcome)).to eq(%w[projected scheduled])
      expect(reports.pluck(:game_id).uniq.size).to eq(1)
      expect(Game.where(season:).count).to eq(1)
      expect(TeamGame.where(game_id: reports.pluck(:game_id)).count).to eq(2)
      expect(GameExternalIdentity.where(game_id: reports.pluck(:game_id)).count).to eq(1)
    end
  end

  def start_first_writer
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Game.transaction do
          results << described_class.new(observation: payload, season:).call
          first_applied << true
          release_first.pop
        end
      end
    end
  end

  def start_second_writer(values = payload.merge(provider: "second-#{token}"))
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        second_pid << connection.select_value('SELECT pg_backend_pid()')
        results << described_class.new(observation: values, season:).call
      end
    end
  end

  def wait_for_advisory_waiter(pid)
    Timeout.timeout(10) do
      loop do
        wait = ActiveRecord::Base.connection.select_value("SELECT wait_event FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
        break if wait == 'advisory'

        sleep(0.01)
      end
    end
  end
end
