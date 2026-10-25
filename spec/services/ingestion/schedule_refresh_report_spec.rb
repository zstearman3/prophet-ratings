# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScheduleRefreshReport do
  it 'keeps name-only box coverage distinct and identifies per-game rollback safely' do
    report = described_class.call(final_box_coverage: { not_applicable: 2, complete: 3, private: 'sensitive' },
                                  games: [{ reason: 'game_rolled_back: points: component mismatch', outcome: 'invalid' }])
    expect(report['final_box_coverage']).to eq('not_applicable' => 2, 'complete' => 3)
    expect(report.dig('games', 0, 'reason')).to eq('game_rolled_back')
    expect(report.to_json).not_to include('sensitive')
  end

  it 'retains only known scope and quota evidence without source messages, headers, paths or payloads' do
    source = { scope: { provider: 'cbbd', contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1',
                        adapter_revision: Ingestion::Cbbd::ImportObservation::REVISION, api_key: 'sensitive' },
               acquisition: { complete: false, attempts: 2, retries: 1, latest_quota_headers: { private: 'sensitive' },
                              failures: [{ reason: 'quota', evidence: { raw: 'sensitive' } }, { reason: 'sensitive' }] },
               error: 'sensitive', manifest: '/private/sensitive', raw_payload: 'sensitive' }
    result = described_class.call(source)
    expect(result.dig('scope', 'provider')).to eq('cbbd')
    expect(result.dig('acquisition', 'failure_reasons')).to eq(['quota'])
    expect(result.to_json).not_to include('sensitive', 'latest_quota_headers', 'raw_payload', 'manifest')
  end
end
