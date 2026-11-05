# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameSyncRun do
  include_context 'with scoring review evidence'

  let(:acquisition) { CbbdReviewRun.create!(season:, start_date: date, end_date: date, maximum_requests: 2, retries: 0) }
  let(:invalid) do
    row.deep_dup.tap do |value|
      value['source_game_id'] = '2'
      value['source_completed'] = false
      value['completion_evidence'] = nil
      value['reasons'] = ['source not confirmed final with unequal valid scores']
    end
  end

  def sync(rows, **)
    allow(acquisition).to receive(:verified_sync_replay).and_return(
      'complete' => true, 'observations' => rows, 'acquisition' => { 'complete' => true, 'attempts' => 2 }
    )
    Ingestion::GameSyncRun.new(season:, dates: [date], resume: false, provider: 'cbbd',
                               provider_options: { prepared_run: acquisition }, **).call
  end

  it 'commits valid games after a bad game and reports held coverage separately from processing', :aggregate_failures do
    report = sync([invalid, row])
    expect(Game.sole).to have_attributes(status: 'final', home_team_score: 65)
    expect(report).to include(complete: false, processing_complete: true, failed_dates: [date])
    expect(report[:days].sole).to include(status: 'completed_with_issues', committed_rows: 1)
    expect(GameIngestionIssue.pluck(:category)).to contain_exactly('missing_result', 'scoring')
    expect(GameSyncDate.sole).not_to be_completed
  end

  it 'preserves earlier committed games when a later row unexpectedly fails' do
    allow(Ingestion::Cbbd::ImportObservation).to receive(:new).and_call_original
    allow(Ingestion::Cbbd::ImportObservation).to receive(:new).with(invalid, season).and_raise(IOError, 'synthetic row failure')
    report = sync([row, invalid])
    expect(Game.sole.home_team_score).to eq(65)
    expect(report).to include(complete: false, processing_complete: false)
    expect(report[:days].sole[:operational_failure]).to be(true)
  end

  it 'does not undo a committed result when report persistence fails' do
    callback = ->(_day) { raise IOError, 'synthetic report failure' }
    expect { sync([row], on_day: callback) }.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(Game.sole).to be_final
  end
end
