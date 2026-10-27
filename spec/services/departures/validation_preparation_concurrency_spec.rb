# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Departures::ValidationPreparation do
  self.use_transactional_tests = false

  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { legacy_departure_batch(season) }
  let(:threads) { [] }
  let(:held) { Queue.new }
  let(:release) { Queue.new }

  before do
    create(:team_season, season:, team:)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
  end

  after do
    3.times { release << true }
    threads.each { |thread| thread.join(10) }
    # Sealed certificates deliberately reject DELETE. This disposable test database owns these fixtures.
    dataset_ids = DepartureValidation.where(departure_batch_id: batch.id).pluck(:departure_dataset_normalization_id).compact
    source_ids = DepartureDatasetNormalization.where(id: dataset_ids).pluck(:source_normalization_ids).flat_map(&:values).uniq
    capture_ids = DepartureSourceNormalization.where(id: source_ids).pluck(:departure_source_capture_id)
    ApplicationRecord.connection.execute('TRUNCATE departure_validations CASCADE')
    DepartureDatasetRow.where(departure_dataset_normalization_id: dataset_ids).delete_all
    DepartureDatasetNormalization.where(id: dataset_ids).delete_all
    DepartureNormalizedRow.where(departure_source_normalization_id: source_ids).delete_all
    DepartureSourceNormalization.where(id: source_ids).delete_all
    DepartureSourceCapture.where(id: capture_ids).delete_all
    TeamOffseasonProfile.where(team_season_id: season.team_seasons.select(:id)).delete_all
    DepartureCaptureObservation.where(departure_acquisition_id: batch.acquisitions.select(:id)).delete_all
    DepartureAcquisition.where(departure_batch_id: batch.id).delete_all
    DepartureBatch.where(id: batch.id).delete_all
    OffseasonInputRevision.where(season:).delete_all
    season.destroy!
    team.destroy!
  end

  def in_connection(&)
    threads << Thread.new { ApplicationRecord.connection_pool.with_connection(&) }
  end

  def prepared
    operation = described_class.create(batch)
    described_class.new(operation).call
    operation.reload
  end

  def assert_writer_blocked(pid)
    Timeout.timeout(8) do
      loop do
        state = ApplicationRecord.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
        break if state == 'Lock'

        sleep 0.01
      end
    end
  end

  it 'returns prompt contention for a new approval and returns an existing approval without waiting' do
    operation = prepared
    in_connection do |connection|
      connection.transaction do
        described_class.lock_generation
        held << true
        release.pop
      end
    end
    Timeout.timeout(8) { held.pop }
    Timeout.timeout(1) do
      expect { Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com') }.to raise_error(ArgumentError, /busy/)
    end
    release << true
    threads.each(&:join)
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    in_connection do |connection|
      connection.transaction do
        described_class.lock_generation
        held << true
        release.pop
      end
    end
    Timeout.timeout(8) { held.pop }
    Timeout.timeout(1) do
      expect(Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com').id).to eq(approval.id)
    end
  end

  it 'holds the same invalidation lock from final validation comparison until the ready certificate commits' do
    operation = described_class.create(batch)
    preparer = described_class.new(DepartureValidation.find(operation.id))
    allow(preparer).to receive(:ready).and_wrap_original do |method, *args|
      method.call(*args)
      held << true
      release.pop
    end
    in_connection { preparer.call }
    Timeout.timeout(8) { held.pop }
    writer_pid = Queue.new
    in_connection do |connection|
      writer_pid << connection.select_value('SELECT pg_backend_pid()')
      connection.execute("UPDATE teams SET school = 'Changed after seal' WHERE id = #{Integer(team.id)}")
    end
    assert_writer_blocked(Timeout.timeout(8) { writer_pid.pop })
    expect(operation.reload.status).to eq('running')
    release << true
    threads.each { |thread| expect(thread.join(10)).to be_present }
    expect(operation.reload.status).to eq('ready')
    expect(operation).not_to be_current
  end

  it 'holds the invalidation lock through publication commit and exposes a following SQL edit as stale', :aggregate_failures do
    operation = prepared
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    publisher = Departures::ValidationPublication.new(DepartureApproval.find(approval.id))
    allow(publisher).to receive(:publish_batch).and_wrap_original do |method, *args|
      method.call(*args)
      held << true
      release.pop
    end
    in_connection { publisher.call }
    Timeout.timeout(8) { held.pop }
    writer_pid = Queue.new
    in_connection do |connection|
      writer_pid << connection.select_value('SELECT pg_backend_pid()')
      connection.execute("UPDATE teams SET school = 'Changed after publication' WHERE id = #{Integer(team.id)}")
    end
    assert_writer_blocked(Timeout.timeout(8) { writer_pid.pop })
    expect(OffseasonInputRevision.where(season:).count).to eq(0)
    expect(TeamOffseasonProfile.where(team_season_id: season.team_seasons.select(:id)).count).to eq(0)
    release << true
    threads.each { |thread| expect(thread.join(10)).to be_present }
    expect(operation.reload.status).to eq('published')
    expect(operation).not_to be_current
    expect(DepartureProgress.new(season).call.status).to eq('needs_review')
  end
end
