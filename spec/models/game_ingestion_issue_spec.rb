# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameIngestionIssue do
  let(:season) { create(:season) }
  let(:admin) { create(:user, :admin) }

  def observation(score = 65)
    GameObservation.create!(provider: 'cbbd', external_game_id: 'synthetic-1', outcome: 'invalid', reason: 'points: component mismatch',
                            normalized_payload: { home: { name: 'Synthetic Home', score: }, away: { name: 'Synthetic Away', score: 64 },
                                                  schedule_date: season.start_date.iso8601 })
  end

  it 'deduplicates identical polls without discarding acknowledgment, and reopens changed facts', :aggregate_failures do
    first = observation
    issue = described_class.capture!(season:, observation: first, category: 'scoring')
    issue.decisions.create!(actor: admin, action: 'acknowledge', source_fingerprint: issue.source_fingerprint,
                            comparison_fingerprint: issue.comparison_fingerprint, values: {})
    issue.update!(state: 'resolved')
    repeated = described_class.capture!(season:, observation: observation, category: 'scoring')
    expect(repeated.id).to eq(issue.id)
    expect(repeated).to have_attributes(state: 'resolved', original_observation_id: first.id)
    changed = described_class.capture!(season:, observation: observation(66), category: 'scoring')
    expect(changed.id).to eq(issue.id)
    expect(changed.state).to eq('open')
    expect(changed.decisions.sole.message).to eq('Acknowledged by admin')
    expect(described_class.count).to eq(1)
  end

  it 'retains decisions immutably and rejects unprivileged decisions' do
    issue = described_class.capture!(season:, observation: observation, category: 'scoring')
    decision = issue.decisions.create!(actor: admin, action: 'select_scores', source_fingerprint: issue.source_fingerprint,
                                       comparison_fingerprint: issue.comparison_fingerprint, values: { home: 65 })
    expect(decision.message).to eq('Approved by admin')
    expect { decision.update!(values: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { decision.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(issue.decisions.new(actor: create(:user), action: 'acknowledge', source_fingerprint: 'x',
                               comparison_fingerprint: 'x')).not_to be_valid
  end
end
