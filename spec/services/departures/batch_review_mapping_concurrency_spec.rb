# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Departures::BatchReview do
  self.use_transactional_tests = false

  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { Departures::BatchPreparation.create(season, cbbd_fields) }
  let(:locked) { Queue.new }
  let(:release) { Queue.new }
  let(:writer_pid) { Queue.new }
  let(:threads) { [] }

  before do
    create(:team_season, season:, team:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    capture_cbbd(batch)
  end

  after do
    release << true
    threads.each { |thread| thread.join(10) }
    TeamExternalIdentity.where(team:).delete_all
    operations = DepartureValidation.where(departure_batch_id: batch.id)
    dataset_ids = batch.acquisitions.pluck(Arel.sql("(dataset->>'normalization_id')::bigint")).compact +
                  operations.pluck(:departure_dataset_normalization_id).compact
    DepartureApproval.where(departure_validation_id: operations.select(:id)).delete_all
    DepartureProposal.where(departure_validation_id: operations.select(:id)).delete_all
    operations.delete_all
    DepartureDatasetRow.where(departure_dataset_normalization_id: dataset_ids).delete_all
    DepartureDatasetNormalization.where(id: dataset_ids).delete_all
    observations = DepartureCaptureObservation.where(departure_acquisition_id: batch.acquisitions.select(:id))
    capture_ids = observations.pluck(:departure_source_capture_id)
    normalizations = DepartureSourceNormalization.where(departure_source_capture_id: capture_ids)
    DepartureNormalizedRow.where(departure_source_normalization_id: normalizations.select(:id)).delete_all
    normalizations.delete_all
    observations.delete_all
    DepartureSourceCapture.where(id: capture_ids).delete_all
    DepartureAcquisition.where(departure_batch: batch).delete_all
    batch.reload.destroy!
    season.destroy!
    team.destroy!
  end

  def in_connection(&)
    threads << Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }
  end

  def wait_for_writer
    pid = Timeout.timeout(8) { writer_pid.pop }
    Timeout.timeout(8) do
      loop do
        state = ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
        return state if state == 'Lock'

        sleep 0.01
      end
    end
  end

  it 'pins absent provider mappings until the v2 save transaction has committed' do
    allow(described_class).to receive(:lock_provider_mappings).and_wrap_original do |original|
      original.call
      locked << true
      release.pop
    end
    key = described_class.new(batch).review_key
    in_connection do
      described_class.new(DepartureBatch.find(batch.id)).save('review_key' => key, 'rows' => cbbd_rows(team))
    end
    Timeout.timeout(8) { locked.pop }
    in_connection do |connection|
      writer_pid << connection.select_value('SELECT pg_backend_pid()')
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '30')
    end
    expect(wait_for_writer).to eq('Lock')
    release << true
    expect(threads.map { |thread| thread.join(10) }).to all(be_present)
    expect(TeamExternalIdentity.where(provider: 'cbbd', external_id: '30').pick(:team_id)).to eq(team.id)
    expect(batch.reload.decisions.size).to eq(60)
  end
end
