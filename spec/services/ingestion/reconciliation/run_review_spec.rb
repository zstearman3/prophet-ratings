# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Reconciliation::RunReview do
  include_context 'with synthetic reconciliation'

  let(:run) do
    value = CbbdReviewRun.create!(season:, start_date: '2025-11-01', end_date: '2025-11-02', maximum_requests: 4, retries: 0,
                                  status: 'completed', manifest: { 'finalized' => true, 'acquisition' => { 'captures' => [] } },
                                  normalized_replay: replay)
    value.update!(evidence_digest: value.evidence_hash)
    value
  end
  let(:review) { described_class.new(run) }
  let(:reviewer) { create(:user, email: 'admin@example.test') }

  before { game }

  def submission(comparison, rows)
    { 'comparison_id' => comparison.id.to_s, 'draft_revision' => comparison.reload.draft_revision.to_s, 'rows' => rows }
  end

  def draft_rows
    choices.map { |choice| choice.merge('selected' => '1', 'deferred' => '0') }
  end

  it 'merges pages, explicitly saves unchecked browser controls, and atomically applies only approvals' do
    comparison = review.compare
    review.save(submission(comparison, draft_rows.first(2)))
    review.save(submission(comparison, draft_rows.last(1)))
    expect(comparison.reload.draft.size).to eq(3)
    decision = review.apply(submission(comparison, []).merge('reason' => 'Reviewed retained evidence', 'confirm' => '1'), reviewer:)
    expect(decision.reviewer).to eq("User #{reviewer.id}: #{reviewer.email}")
    expect(decision.result['mappings'].size).to eq(3)
    expect(review.apply(submission(comparison, []).merge('reason' => 'Reviewed retained evidence', 'confirm' => '1'),
                        reviewer:)).to eq(decision)
    expect { review.save(submission(comparison, draft_rows)) }.to raise_error(ArgumentError, /applied/)
  end

  it 'keeps defer and target selection separate from approval and rejects stale drafts' do
    comparison = review.compare
    old = submission(comparison, draft_rows.first(1))
    review.save(old)
    expect { review.save(old) }.to raise_error(ArgumentError, /changed/)
    review.save(submission(comparison, [draft_rows.first.merge('selected' => '0', 'deferred' => '1')]))
    expect(comparison.reload.draft.values.first).to include('selected' => false, 'deferred' => true)
    expect do
      review.apply(submission(comparison, []).merge('reason' => 'Review', 'confirm' => '1'), reviewer:)
    end.to raise_error(ArgumentError, /Select/)
  end

  it 'rejects arbitrary targets without saving any rows' do
    comparison = review.compare
    expect { review.save(submission(comparison, [draft_rows.first, draft_rows.last.merge('local_id' => 999_999)])) }
      .to raise_error(ArgumentError, /candidate/)
    expect(comparison.reload.draft).to eq({})
  end

  it 'creates immutable refresh versions, carrying valid intent with every approval cleared' do
    comparison = review.compare
    review.save(submission(comparison, draft_rows))
    replacement = review.compare
    expect(replacement.version).to eq(2)
    expect(replacement.draft.values).to all(include('selected' => false))
    expect { review.save(submission(comparison, draft_rows)) }.to raise_error(ArgumentError, /version/)
    expect { comparison.update!(report: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rejects a stale local alias atomically and refreshes remaining work after partial apply' do
    comparison = review.compare
    review.save(submission(comparison, draft_rows.first(1)))
    create(:team_alias, team: teams.first, value: 'Changed evidence')
    expect { review.apply(submission(comparison, []).merge('reason' => 'Review', 'confirm' => '1'), reviewer:) }
      .to raise_error(ArgumentError, /changed/)
    expect(IdentityMappingDecision.count).to eq(0)
    refreshed = review.compare
    review.save(submission(refreshed, draft_rows.first(1)))
    review.apply(submission(refreshed, []).merge('reason' => 'Review', 'confirm' => '1'), reviewer:)
    remaining = review.compare
    expect(remaining.report['teams'].pluck('status')).to contain_exactly('mapped', 'proposed')
    expect(remaining.draft.values).to all(include('selected' => false))
    expect(GameExternalIdentity.count).to eq(0)
  end

  it 'bulk approves only explicitly visible eligible proposals and validates game participants' do
    comparison = review.compare
    visible = draft_rows.first(1).map { |row| row.merge('selected' => '0', 'local_id' => '') }
    review.save(submission(comparison, visible).merge('bulk' => '1'))
    expect(comparison.reload.selected_choices).to eq(choices.first(1))
    expect do
      review.save(submission(comparison, [draft_rows.last.merge('selected' => '0')]).merge('bulk' => '1',
                                                                                           'filters' => { 'entity' => 'game' }))
    end.to raise_error(ArgumentError, /participant/i)
    expect(comparison.reload.selected_choices).to eq(choices.first(1))
  end

  it 'requires explicit same-game supersession and never mutates canonical records or memberships' do
    old = GameExternalIdentity.associate!(game:, provider: 'cbbd', external_id: 'old-key')
    create(:team_game, game:, team: teams.first, team_season: teams.first.team_seasons.find_by!(season:), home: true, points: 65)
    comparison = review.compare
    review.save(submission(comparison, draft_rows))
    token = submission(comparison, []).merge('reason' => 'Reviewed source replacement', 'confirm' => '1')
    expect { review.apply(token, reviewer:) }.to raise_error(ArgumentError, /supersession/)
    expect(IdentityMappingDecision.count).to eq(0)
    replacement = draft_rows.last.merge('action' => 'supersede', 'supersedes_external_id' => 'old-key')
    review.save(submission(comparison, [replacement]))
    before = [Game.order(:id).map(&:attributes), TeamGame.order(:id).map(&:attributes), TeamSeason.order(:id).map(&:attributes)]
    review.apply(submission(comparison, []).merge('reason' => 'Reviewed source replacement', 'confirm' => '1'), reviewer:)
    after = [Game.order(:id).map(&:attributes), TeamGame.order(:id).map(&:attributes), TeamSeason.order(:id).map(&:attributes)]
    expect(after).to eq(before)
    expect(old.reload).to be_superseded
    expect(GameExternalIdentity.active.find_by!(game:).external_id).to eq('1')
  end

  it 'preserves the applied draft and decision association against later model edits' do
    comparison = review.compare
    review.save(submission(comparison, draft_rows))
    review.apply(submission(comparison, []).merge('reason' => 'Review', 'confirm' => '1'), reviewer:)
    expect { comparison.reload.update!(draft: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
