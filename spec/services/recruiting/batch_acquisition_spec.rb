# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::BatchAcquisition do
  let(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team, school: 'Arkansas') }
  let(:batch) { RecruitingBatch.create!(season:, source_year: 2026) }
  let(:first_html) { Rails.root.join('spec/fixtures/recruiting/page1.html').read }
  let(:second_html) do
    page = Nokogiri::HTML(Rails.root.join('spec/fixtures/recruiting/page2.html').read)
    page.css('a[data-js="showmore"]').remove
    page.to_html
  end

  before do
    allow(Recruiting::Acquisition).to receive(:sleep)
    allow(HTTParty).to receive(:get).and_return(double(code: 200, body: first_html), double(code: 200, body: second_html))
  end

  it 'uses the automated parser to save source pages and normalized database rows without files' do
    described_class.new(batch).call
    expect(batch.reload).to have_attributes(status: 'ready', page_count: 2, source_status: 'ok', next_url: nil)
    expect(batch.entries.order(:row_number).pluck(:source_label)).to eq(%w[Arkansas Nebraska])
    expect(batch.entries.find_by!(source_label: 'Arkansas')).to have_attributes(team_id: team.id, class_points: BigDecimal('70.43'))
    source = JSON.parse(batch.snapshot_bytes).fetch('pages').first
    expect(Base64.strict_decode64(source.fetch('html_base64'))).to eq(first_html)
    expect(batch.dataset.manifest.fetch('rows').size).to eq(2)
  end

  it 'does not fetch a ready batch again or duplicate its rows' do
    described_class.new(batch).call
    before = [batch.reload.attributes, batch.entries.map(&:attributes)]
    described_class.new(batch).call
    expect([batch.reload.attributes, batch.entries.map(&:attributes)]).to eq(before)
    expect(HTTParty).to have_received(:get).twice
  end

  it 'retains failed HTTP evidence and prevents approval rather than creating an empty successful batch' do
    allow(HTTParty).to receive(:get).and_return(double(code: 403, body: 'Blocked source response'))
    described_class.new(batch).call
    expect(batch.reload).to have_attributes(status: 'failed', source_status: 'access_failure')
    expect(batch.failure_message).to be_present
    expect(batch.snapshot_bytes).to include(Base64.strict_encode64('Blocked source response'))
    expect(batch.entries).to be_empty
    expect { Recruiting::BatchReview.new(batch).publish({ 'confirm' => '1' }, reviewer: 'reviewer') }
      .to raise_error(ArgumentError, /unpublished/)
  end

  it 'runs safely through the background job and does not fetch a completed batch twice' do
    AcquireRecruitingBatchJob.perform_now(batch.id)
    expect(batch.reload.status).to eq('ready')
    AcquireRecruitingBatchJob.perform_now(batch.id)
    expect(HTTParty).to have_received(:get).twice
  end
end
