# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Ingestion::Reconciliation::Apply do
  self.use_transactional_tests = false
  include_context 'with synthetic reconciliation'

  let(:threads) { [] }
  let(:locked) { Queue.new }
  let(:release) { Queue.new }
  let(:writer_pid) { Queue.new }
  let(:results) { Queue.new }

  before do
    create(:team_game, game:, team: teams.first, team_season: teams.first.team_seasons.find_by!(season:), home: true, points: 65)
  end

  after do
    release << true
    threads.each { |thread| thread.join(10) }
    IdentityMappingDecision.delete_all
    GameExternalIdentity.where(game_id: season.games.select(:id)).delete_all
    TeamExternalIdentity.where(team: teams).delete_all
    TeamGame.where(game_id: season.games.select(:id)).delete_all
    season.games.delete_all
    season.destroy!
    teams.each(&:destroy!)
  end

  def in_connection(&)
    threads << Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }
  end

  def wait_for_lock(pid)
    Timeout.timeout(8) do
      loop do
        waiting = ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
        break if waiting == 'Lock'

        sleep 0.01
      end
    end
  end

  def hold_apply(comparison)
    allow(described_class).to receive(:lock_tables).and_wrap_original do |original|
      original.call
      locked << true
      release.pop
    end
    submission = decisions(comparison)
    in_connection { results << described_class.new(comparison:, replay:, decisions: submission).call }
    Timeout.timeout(8) { locked.pop }
  end

  %w[candidate alias stat].each do |mutation|
    it "serializes #{mutation} writes behind apply locks and rejects subsequent stale retries" do
      comparison = report
      hold_apply(comparison)
      in_connection do |connection|
        writer_pid << connection.select_value('SELECT pg_backend_pid()')
        case mutation
        when 'candidate'
          create(:game, season:, start_time: '2025-11-02T23:00:00Z', home_team_name: teams.first.school,
                        away_team_name: teams.last.school)
        when 'alias' then create(:team_alias, team: teams.first, value: 'Concurrent synthetic alias')
        when 'stat' then TeamGame.find_by!(game:).update!(points: 99)
        end
      end
      wait_for_lock(Timeout.timeout(8) { writer_pid.pop })
      expect(results).to be_empty
      release << true
      threads.each { |thread| Timeout.timeout(8) { thread.value } }
      expect(results.pop).to be_a(IdentityMappingDecision)
      allow(described_class).to receive(:lock_tables).and_call_original
      expect { apply(comparison) }.to raise_error(ArgumentError, /changed/)
    end
  end

  it 'rolls back within the three-second lock timeout when another writer holds a read table' do
    comparison = report
    in_connection do
      TeamAlias.transaction do
        create(:team_alias, team: teams.first, value: 'Held synthetic alias')
        locked << true
        release.pop
      end
    end
    Timeout.timeout(8) { locked.pop }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { apply(comparison) }.to raise_error(described_class::RetryableConflict, /rolled back/)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be_between(2.5, 6)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end
end
