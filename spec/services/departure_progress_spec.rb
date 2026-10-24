# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DepartureProgress do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:membership) { create(:team_season, team:, season:) }
  let(:batch) { legacy_departure_batch(season) }

  before do
    membership
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    approve_departures(batch)
  end

  def acquired_records(&)
    count = 0
    subscriber = lambda do |*, event|
      count += event.fetch(:record_count) if event[:class_name] == 'DepartureAcquisition'
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record', &)
    count
  end

  it 'projects only comparison fields from the stored revision while retaining the original evidence' do
    progress = described_class.new(season)
    revision = progress.send(:revision)
    expect(revision.payload.keys).to contain_exactly('team_inputs', 'report')
    expect(revision.payload.fetch('team_inputs').keys).to eq([team.id.to_s])
    expect(OffseasonInputRevision.find(revision.id).payload.keys).to include('dataset', 'review')
    expect(progress.call.status).to eq('complete')
  end

  it 'replays full retained evidence once without loading the acquisition again for its status' do
    loaded_datasets = []
    allow(Departures::RetainedEvidence).to receive(:new).and_wrap_original do |original, acquisition, **options|
      loaded_datasets << %i[dataset evidence].map { |name| acquisition.has_attribute?(name) }
      original.call(acquisition, **options)
    end
    records = acquired_records { expect(described_class.new(season).call.status).to eq('complete') }
    expect(records).to eq(1)
    expect(Departures::RetainedEvidence).to have_received(:new).once
    expect(loaded_datasets).to eq([[false, false]])
  end

  it 'does not retain replay source bodies in the surrounding request query cache' do
    cached_reads = []
    callback = lambda do |*, event|
      sql = event[:sql]
      full_source_read = sql.start_with?('SELECT "departure_acquisitions".*') || sql.include?('"departure_acquisitions"."evidence"')
      source_scalar = sql.include?('jsonb_extract_path_text(evidence')
      cached_reads << event[:cached] if sql.start_with?('SELECT') && (full_source_read || source_scalar)
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      ActiveRecord::Base.cache do
        expect(described_class.new(season).call.status).to eq('complete')
        batch.attempt
      end
    end
    expect(cached_reads.size).to eq(batch.plan.fetch('sources').size + 1)
    expect(cached_reads).not_to include(true)
  end

  it 'checks stale profile pointers and reads acquisition status without instantiating source payloads' do
    membership.team_offseason_profile.update!(departure_revision: nil)
    records = acquired_records do
      progress = described_class.new(season).call
      expect(progress.status).to eq('needs_review')
      expect(progress.last_result).to include('acquisition completed')
    end
    expect(records).to eq(0)
  end

  it 'still replay-validates current identity mappings rather than trusting the projected saved report' do
    team.update!(school: 'Changed canonical identity')
    expect(described_class.new(season).call.status).to eq('needs_review')
  end
end
