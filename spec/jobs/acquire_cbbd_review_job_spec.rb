# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AcquireCbbdReviewJob do
  it 'loads state inside the advisory lock so a waiting duplicate cannot refetch completed work' do
    run = CbbdReviewRun.create!(season: create(:season, year: 2026), start_date: '2025-11-01', end_date: '2025-11-02',
                                maximum_requests: 2, retries: 0)
    allow(GoodJob::Job).to receive(:advisory_lock_key) do |*, &block|
      run.update!(status: 'completed')
      block.call
    end
    described_class.perform_now(run.id)
    expect(run.reload.status).to eq('completed')
    expect(run.captures).to be_empty
  end
end
