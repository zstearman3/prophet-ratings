# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Ingestion::Reconciliation::RunReview do
  self.use_transactional_tests = false
  include_context 'with synthetic reconciliation'

  let(:threads) { [] }
  let(:locked) { Queue.new }
  let(:release) { Queue.new }
  let(:results) { Queue.new }
  let(:writer_pid) { Queue.new }
  let(:reviewer) { create(:user, admin: true) }
  let(:run) do
    value = CbbdReviewRun.create!(season:, start_date: '2025-11-01', end_date: '2025-11-02', maximum_requests: 4, retries: 0,
                                  status: 'completed', manifest: { 'finalized' => true, 'acquisition' => { 'captures' => [] } },
                                  normalized_replay: replay)
    value.update!(evidence_digest: value.evidence_hash)
    value
  end

  after do
    release << true
    threads.each { |thread| thread.join(10) }
    run.update!(active_comparison_id: nil)
    CbbdReviewComparison.where(cbbd_review_run_id: run.id).delete_all
    run.destroy!
    IdentityMappingDecision.delete_all
    GameExternalIdentity.where(game_id: season.games.select(:id)).delete_all
    TeamExternalIdentity.where(team: teams).delete_all
    TeamGame.where(game_id: season.games.select(:id)).delete_all
    season.games.delete_all
    season.destroy!
    teams.each(&:destroy!)
    reviewer.destroy!
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

  def hold_apply(token)
    allow(Ingestion::Reconciliation::Apply).to receive(:lock_tables).and_wrap_original do |original|
      original.call
      locked << true
      release.pop
    end
    actor = reviewer
    in_connection { results << described_class.new(CbbdReviewRun.find(run.id)).apply(token, reviewer: actor) }
  end

  %w[save compare].each do |action|
    it "serializes actual #{action} against apply using separate connections" do
      game
      review = described_class.new(run)
      comparison = review.compare
      token = { 'comparison_id' => comparison.id, 'draft_revision' => 0,
                'rows' => choices.map { |choice| choice.merge('selected' => '1') } }
      review.save(token)
      token.merge!('draft_revision' => 1, 'reason' => 'Concurrent synthetic review', 'confirm' => '1')
      hold_apply(token)
      Timeout.timeout(8) { locked.pop }
      in_connection do |connection|
        writer_pid << connection.select_value('SELECT pg_backend_pid()')
        worker = described_class.new(CbbdReviewRun.find(run.id))
        results << (action == 'save' ? worker.save(token) : worker.compare)
      rescue ArgumentError => error
        results << error
      end
      wait_for_lock(Timeout.timeout(8) { writer_pid.pop })
      release << true
      threads.each { |thread| Timeout.timeout(8) { thread.value } }
      outcomes = Array.new(2) { results.pop }
      expect(outcomes).to include(an_instance_of(IdentityMappingDecision))
      if action == 'save'
        expect(outcomes).to include(an_instance_of(ArgumentError))
        expect(comparison.reload.draft_revision).to eq(1)
      else
        expect(run.reload.active_comparison.version).to eq(2)
        expect(run.active_comparison.draft.values).to all(include('selected' => false))
      end
    end
  end
end
