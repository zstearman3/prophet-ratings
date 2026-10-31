# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncOddsJob do
  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  let(:failure) do
    {
      odds_api_game_id: 'unmatched-game',
      home_team: 'Unknown Home',
      away_team: 'Unknown Away',
      commence_time: '2026-03-01T17:01:26Z',
      error_class: 'ActiveRecord::RecordNotFound',
      message: 'Could not match game teams from odds payload'
    }
  end

  let(:result) do
    instance_double(
      OddsApi::SyncService::Result,
      fetched_count: 2,
      imported_count: 1,
      failed_count: 1,
      failures: [failure]
    )
  end

  it 'logs the import results and enqueues recommendations even with partial import failures' do
    allow(OddsApi::SyncService).to receive(:call).and_return(result)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)

    expect { described_class.perform_now }.to have_enqueued_job(GenerateBetRecommendationsJob)

    aggregate_failures do
      expect(OddsApi::SyncService).to have_received(:call)
      expect(Rails.logger).to have_received(:info).with(
        'Odds API sync complete: fetched=2 imported=1 failed=1'
      )
      expect(Rails.logger).to have_received(:warn).with(
        'Odds API sync failure: odds_api_game_id=unmatched-game home_team=Unknown Home away_team=Unknown Away ' \
        'commence_time=2026-03-01T17:01:26Z error_class=ActiveRecord::RecordNotFound ' \
        'message=Could not match game teams from odds payload'
      )
    end
  end

  it 'does not enqueue recommendations when the odds fetch fails' do
    allow(OddsApi::SyncService).to receive(:call).and_raise(StandardError, 'API unavailable')

    expect { described_class.perform_now }.not_to have_enqueued_job(GenerateBetRecommendationsJob)
  end
end
