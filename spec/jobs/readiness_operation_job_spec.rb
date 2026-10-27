# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReadinessOperationJob do
  include ReadinessFixture

  let(:season) { create(:season) }
  let(:admin) { create(:user, :admin) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:row) { create(:team_season, season:) }

  before { allow(PublishPreseasonJob).to receive(:perform_later).and_return(true) }

  it 'builds a report and retains its result once even if the delivery repeats' do
    operation = OffseasonReadinessOperation.create!(season:, actor: admin, action: 'report')
    described_class.perform_now(operation.id)
    expect(operation.reload.status).to eq('completed')
    expect(operation.report.fetch('fingerprint')).to be_present
    allow(OffseasonReadiness).to receive(:new).and_call_original
    described_class.perform_now(operation.id)
    expect(OffseasonReadiness).not_to have_received(:new)
  end

  it 'records a reviewed report and rejects stale activation with an audit attempt', :aggregate_failures do
    publish_readiness_fixture(season, model, row, admin)
    report = OffseasonReadiness.new(season).call
    operation = OffseasonReadinessOperation.create!(season:, actor: admin, action: 'review',
                                                    inputs: { fingerprint: report.fetch('fingerprint'), acknowledge: '1', deferrals: {} })
    described_class.perform_now(operation.id)
    expect(operation.reload.status).to eq('completed')
    review = operation.offseason_readiness_review
    expect(review.fingerprint).to eq(report.fetch('fingerprint'))
    season.update!(end_date: season.end_date + 1)
    activation = OffseasonReadinessOperation.create!(season:, actor: admin, action: 'season', offseason_readiness_review: review)
    described_class.perform_now(activation.id)
    expect(activation.reload.status).to eq('failed')
    expect(activation.error_message).to include('stale')
    expect(review.reload.attempts.last['status']).to eq('failed')
    expect(season.reload).not_to be_current
  end

  it 'activates once and replays the completed delivery without switching back' do
    publish_readiness_fixture(season, model, row, admin)
    review = save_readiness_review(season, admin)
    operation = OffseasonReadinessOperation.create!(season:, actor: admin, action: 'season', offseason_readiness_review: review)
    described_class.perform_now(operation.id)
    expect(operation.reload.status).to eq('completed')
    expect(season.reload).to be_current
    other = create(:season, year: 2030)
    season.update!(current: false)
    other.update!(current: true)
    described_class.perform_now(operation.id)
    expect(Season.current).to eq(other)
  end
end
