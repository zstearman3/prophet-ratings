# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduleRefreshRun do
  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:attributes) do
    { season:, requested_by: create(:user, :admin), provider: 'sports_reference', start_date: today.to_s, end_date: (today + 2.days).to_s }
  end

  before { allow(Game).to receive(:current_schedule_date).and_return(today) }

  it 'persists a fixed inclusive requested date set and rejects ambiguous raw dates' do
    run = described_class.create!(attributes)
    expect(run.requested_dates).to eq((today..(today + 2.days)).map(&:iso8601))
    expect(described_class.new(attributes.merge(start_date: '2026-11-1'))).not_to be_valid
    expect(described_class.new(attributes.merge(start_date: (today - 1.day).to_s))).not_to be_valid
  end

  it 'derives a linked sparse retry without successful dates or a live parent' do
    run = described_class.create!(attributes)
    expect { run.build_retry(attributes[:requested_by]) }.to raise_error(ArgumentError, /terminal/)
    run.update!(status: 'incomplete', report: { days: [{ date: today.to_s }, { date: (today + 1.day).to_s, error: 'failed' }] })
    retry_run = run.build_retry(attributes[:requested_by])
    retry_run.save!
    expect(retry_run.requested_dates).to eq([(today + 1.day).to_s, (today + 2.days).to_s])
    expect(retry_run.retry_of).to eq(run)
  end

  it 'retains fixed numeric CBBD budgets and refuses later scope edits' do
    run = described_class.create!(attributes.merge(provider: 'cbbd', max_requests: 4, retries: 1))
    expect { run.update!(max_requests: 8) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
