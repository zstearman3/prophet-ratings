# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Departures::BatchAcquisition do
  self.use_transactional_tests = false

  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team) }
  let(:batch) { Departures::BatchPreparation.create(season, cbbd_fields) }
  let(:started) { Queue.new }
  let(:release) { Queue.new }
  let(:requests) { [] }
  let(:threads) { [] }

  before do
    create(:team_season, season:, team:)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('synthetic-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |uri, _key|
      requests << uri.path
      if requests.size == 1
        started << true
        release.pop
      end
      { status: 200, body: '[]', headers: {} }
    end
  end

  after do
    release << true
    threads.each { |thread| thread.join(10) }
    DepartureAcquisition.where(departure_batch: batch).delete_all
    batch.reload.destroy!
    season.destroy!
    team.destroy!
  end

  it 'allows only one concurrent worker to claim the finite acquisition budget' do
    attempt = Departures::BatchPreparation.new(batch).acquire
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { described_class.new(DepartureAcquisition.find(attempt.id)).call }
    end
    Timeout.timeout(8) { started.pop }
    described_class.new(DepartureAcquisition.find(attempt.id)).call
    expect(requests.size).to eq(1)
    release << true
    expect(threads.first.join(10)).to be_present
    expect(attempt.reload.manifest.fetch('captures').size).to eq(5)
    expect(requests.size).to eq(5)
  end

  it 'prevents an old worker from rewriting a closed attempt after an explicit interrupted retry' do
    first = Departures::BatchPreparation.new(batch).acquire
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { described_class.new(DepartureAcquisition.find(first.id)).call }
    end
    Timeout.timeout(8) { started.pop }
    successor = Departures::BatchPreparation.new(batch).acquire('close_interrupted' => '1')
    release << true
    expect(threads.first.join(10)).to be_present
    expect(first.reload.status).to eq('failed')
    expect(first.evidence).to eq({})
    expect(requests.size).to eq(1)
    expect(successor.reload.status).to eq('queued')
  end
end
