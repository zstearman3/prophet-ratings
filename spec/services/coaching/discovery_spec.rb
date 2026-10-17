# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coaching::Discovery do
  let(:review) { CoachingReview.create!(year: 2027, discovery_status: 'queued') }
  let(:rows) { JSON.parse(file_fixture('coaching_changes/rows.json').read).map { |row| row.fetch('value').symbolize_keys } }
  let(:scraper) { instance_double(Scraper::CoachingChangesScraper, call: rows) }

  before do
    allow(Scraper::CoachingChangesScraper).to receive(:new).with(year: 2027).and_return(scraper)
  end

  it 'fetches and stores candidates through the job before seasons exist and skips completed retries' do
    review.update!(ready: true)
    DiscoverCoachingChangesJob.perform_now(review.id)
    expect(review.reload).to have_attributes(discovery_status: 'complete', discovery_error: nil, ready: false)
    expect(review.discovered_at).to be_present
    expect(CoachingChange.count).to eq(2)
    DiscoverCoachingChangesJob.perform_now(review.id)
    expect(scraper).to have_received(:call).once
    expect(Season.count).to eq(0)
  end

  it 'retains decisions and readiness on source failure without scheduling a futile job retry' do
    candidate = CoachingChange.create!(effective_year: 2027, status: 'rejected')
    review.update!(ready: true)
    original = candidate.attributes
    allow(scraper).to receive(:call).and_raise(Scraper::CoachingChangesScraper::Error, 'HTTP 403')
    job = DiscoverCoachingChangesJob.new(review.id)
    allow(job).to receive(:retry_job)
    job.perform_now
    expect(review.reload).to have_attributes(discovery_status: 'failed', discovery_error: 'HTTP 403', ready: true)
    expect(candidate.reload.attributes).to eq(original)
    expect(job).not_to have_received(:retry_job)
  end

  it 'preserves the original error when recording discovery failure also fails' do
    error = Scraper::CoachingChangesScraper::Error.new('Source unavailable')
    allow(scraper).to receive(:call).and_raise(error)
    allow(review).to receive(:update!).and_call_original
    allow(review).to receive(:update!).with(discovery_status: 'failed', discovery_error: error.message)
                                      .and_raise(ActiveRecord::StatementInvalid, 'Database unavailable')
    expect { described_class.new(review).call }.to(raise_error { |raised| expect(raised).to equal(error) })
  end

  it 'rolls back imported candidates and readiness if recording successful completion fails' do
    review.update!(ready: true)
    allow(review).to receive(:update!).and_call_original
    allow(review).to receive(:update!).with(hash_including(discovery_status: 'complete')).and_raise('Completion failed')

    described_class.new(review).call

    expect(review.reload).to have_attributes(discovery_status: 'failed', discovery_error: 'Completion failed', ready: true)
    expect(CoachingChange.count).to eq(0)
  end
end
