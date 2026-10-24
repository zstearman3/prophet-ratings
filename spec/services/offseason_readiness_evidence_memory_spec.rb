# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonReadinessEvidence do
  let(:season) { create(:season) }

  it 'keeps fingerprint evidence bounded while still detecting changes inside retained JSON' do
    prior = PreseasonPrior.create!(team_season: create(:team_season, season:), ratings_config_version: create(:ratings_config_version),
                                   inputs: { 'retained_source' => 'x' * 100_000 }, outputs: { 'preseason_adj_pace' => 70 })
    evidence = described_class.records(PreseasonPrior.where(id: prior.id))
    expect(evidence.to_json.bytesize).to be < 1_024
    original = described_class.new(season).fingerprint({})
    expect(described_class.new(season).fingerprint({})).to eq(original)

    # Simulate a repair outside immutable model APIs; unchanged timestamps must not hide changed evidence.
    PreseasonPrior.connection.execute(
      "UPDATE preseason_priors SET inputs = '{\"retained_source\":\"changed\"}'::jsonb WHERE id = #{prior.id}"
    )
    expect(described_class.new(season).fingerprint({})).not_to eq(original)
  end

  it 'reads operation summaries without fetching retained source bodies or datasets' do
    batch = DepartureBatch.create!(season:, plan: {})
    batch.acquisitions.create!(status: 'failed', plan: {}, failure: 'Source unavailable',
                               evidence: { 'private' => 'x' * 100_000 }, dataset: { 'private' => 'y' * 100_000 })
    reads = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload.fetch(:sql)
      reads << sql if sql.start_with?('SELECT') && sql.include?('"departure_acquisitions"')
    end
    evidence = described_class.new(season)
    summary = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      expect(evidence.operation_status).to eq('open')
      evidence.operation_summary
    end
    expect(summary.last).to include('operation' => 'DepartureAcquisition', 'status' => 'failed', 'failure' => 'Source unavailable')
    expect(reads).not_to include(a_string_matching(/SELECT "departure_acquisitions"\.\*/))
    expect(reads.size).to eq(1)
  end
end
