# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/content')
require Rails.root.join('script/performance/departure_cbbd_content')
require Rails.root.join('script/performance/runner')
require Rails.root.join('script/performance/phase_queue')

RSpec.describe OffseasonPerformance::DepartureCbbdContent do
  it 'retains the original benchmark default scenarios and makes normalization explicitly opt-in' do
    options = OffseasonPerformance::RunOptions.parse(%w[--scenario departure_normalization --scale 2])
    expect(options).to include(scenario: 'departure_normalization', scale: 2)
    expect(OffseasonPerformance::Runner::SCENARIOS).not_to include('departure_normalization')
    expect(OffseasonPerformance::RunVerdict.phase_count('departure_normalization')).to eq(2)
  end

  it 'maps the public scenario name into the existing safe queue phase grammar' do
    phase = 'departure_normalization-legacy'.tr('_', '-')
    queue = OffseasonPerformance::PhaseQueue.name('offseason-123abc', phase, 'heavy')
    expect(queue).to include('departure-normalization-legacy')
  end

  it 'exercises all365teams and15stints per scope with a shared athlete and60distinct actual picks' do
    content = described_class.new
    regular = content.players('regular')
    postseason = content.players('postseason')
    picks = Departures::CbbdSelections.new(content.picks, described_class.plan).call
    expect([regular.size, postseason.size]).to eq([5475, 5475])
    expect(regular.pluck('teamId').uniq.size).to eq(365)
    expect(picks.pluck('provider_athlete_id').uniq.size).to eq(60)
    expect(regular.select { |row| row['athleteId'] == 1 }.pluck('teamId')).to eq([1, 2])
    expect(content.teams('postseason').size).to eq(365)
  end

  context 'with benchmark wiring' do
    let(:fixture) { { 'season_id' => 1, 'departure_id' => 2 } }

    before do
      require Rails.root.join('script/performance/departure_sources')
      require Rails.root.join('script/performance/departure_normalization')
    end

    it 'starts exactly two measured phases while retaining the default scenario set' do
      runner = OffseasonPerformance::Runner.allocate
      run = instance_double(OffseasonPerformance::DockerRun)
      result = {}
      runner.instance_variable_set(:@run, run)
      runner.instance_variable_set(:@result, result)
      phase = instance_double(OffseasonPerformance::PhaseRunner, call: nil)
      allow(OffseasonPerformance::PhaseRunner).to receive(:new).and_return(phase)
      runner.send(:run_scenario, 'departure_normalization')
      expect(OffseasonPerformance::PhaseRunner).to have_received(:new).with(run, result,
                                                                            { scenario: 'departure_normalization', phase: 'legacy' })
      expect(OffseasonPerformance::PhaseRunner).to have_received(:new).with(run, result,
                                                                            { scenario: 'departure_normalization', phase: 'cbbd' })
      expect(phase).to have_received(:call).twice
    end

    it 'uses a valid phase queue prefix for worker and job delivery' do
      Dir.mktmpdir do |directory|
        environment = {}
        run = instance_double(OffseasonPerformance::DockerRun, env: environment, directory:, compose: nil)
        phase = OffseasonPerformance::PhaseRunner.new(run, {}, { scenario: 'departure_normalization', phase: 'legacy' })
        allow(phase).to receive(:boot)
        phase.restart
        expect(environment.fetch('BENCHMARK_PHASE')).to eq('departure-normalization-legacy')
        queue = OffseasonPerformance::PhaseQueue.name('offseason-123abc', environment.fetch('BENCHMARK_PHASE'), 'heavy')
        expect(queue).to end_with('departure-normalization-legacy_heavy')
      end
    end

    it 'recognizes both job result files and their byte definition' do
      require Rails.root.join('script/performance/job_output')
      allow(File).to receive(:size).with('/benchmark/departure-normalization-legacy.json').and_return(123)
      allow(File).to receive(:size).with('/benchmark/departure-normalization-cbbd.json').and_return(456)
      legacy = OffseasonPerformance::LegacyDepartureNormalizationJob.new(1)
      cbbd = OffseasonPerformance::CbbdDepartureNormalizationJob.new(2)
      expect(OffseasonPerformance::JobOutput.bytes(legacy)).to eq(123)
      expect(OffseasonPerformance::JobOutput.bytes(cbbd)).to eq(456)
      expect(OffseasonPerformance::JobOutput.definition(cbbd)).to include('JSON file bytes')
    end

    it 'routes collection and skips HTTP sample assertions for this terminal job scenario' do
      require Rails.root.join('script/performance/driver')
      scenario = OffseasonPerformance::Scenario.new('departure_normalization', 'legacy', fixture)
      driver = OffseasonPerformance::Driver.allocate
      driver.instance_variable_set(:@scenario, scenario)
      result = { 'failures' => [] }
      allow(OffseasonPerformance::DepartureNormalizationDriver).to receive(:call).with(result, scenario).and_return(result)
      allow(driver).to receive(:check)
      expect(driver.execute(result)).to eq(result)
      expect(driver).not_to have_received(:check)
      expect(OffseasonPerformance::DepartureNormalizationDriver).to have_received(:call)
    end

    it 'rejects incomplete phases and erroneous terminal outputs' do
      require Rails.root.join('script/performance/driver')
      results = [{ 'scenario' => 'departure_normalization', 'phase' => 'legacy', 'failures' => [] }]
      expect(OffseasonPerformance::RunVerdict.scenario_coverage(results, 'departure_normalization')).to eq('incomplete')
      expect { OffseasonPerformance::DepartureNormalizationDriver.verify({ 'status' => 'failed' }, nil) }.to raise_error(/did not complete/)
      expect { OffseasonPerformance::JobDriver.verify_job_output({ 'terminal' => 'failed' }, 'synthetic') }.to raise_error(/Job failed/)
    end

    it 'fails promptly after a stopped worker leaves its sampler stale' do
      require Rails.root.join('script/performance/departure_normalization_driver')
      allow(File).to receive(:mtime).with('/benchmark/worker-current.json').and_return(Time.current - 61)
      expect { OffseasonPerformance::DepartureNormalizationDriver.verify_worker }.to raise_error(/Worker sampler stale/)
    end

    it 'executes the actual CBBD HeavyJob to its terminal persisted result with a scalar argument' do
      stub_const('OffseasonPerformance::Content::TEAMS', 3)
      season = create(:season, year: 2026)
      retained = nil
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with('/benchmark/departure-normalization-cbbd.json', anything) do |_path, bytes|
        retained = JSON.parse(bytes)
        bytes.bytesize
      end
      job = OffseasonPerformance::CbbdDepartureNormalizationJob.perform_now(season.id)
      expect(job).not_to be(false)
      expect(retained).to include('status' => 'completed', 'source_count' => 5, 'observation_count' => 5,
                                  'player_observations' => 90)
      expect(retained.fetch('summary')).to include('production' => 3, 'failures' => 0)
      attempt = DepartureAcquisition.find(retained.fetch('attempt_id'))
      expect(Departures::RetainedEvidence.new(attempt).verified_dataset(attempt.plan).fetch('production').size).to eq(3)
    end

    it 'executes the exact-corpus adapter and matches file replay on a small correctness fixture' do
      require Rails.root.join('script/performance/evidence_fixture')
      stub_const('OffseasonPerformance::Content::TEAMS', 3)
      stub_const('OffseasonPerformance::Content::CAPTURES', 1)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('BENCHMARK_SCALE').and_return('1')
      season = create(:season, year: 2026)
      original = nil
      expected = nil
      Dir.mktmpdir do |directory|
        storage = { directory:, evidence: {} }
        content = OffseasonPerformance::Content.new(scale: 1)
        sources = content.each_source.map { |source, html| OffseasonPerformance::EvidenceFixture.retain_source(source, html, storage) }
        manifest = OffseasonPerformance::Content.plan.merge('sources' => sources)
        expected = Departures::AnnualDataset.new(manifest:, directory:).call
        batch = DepartureBatch.create!(season:, plan: manifest)
        original = batch.acquisitions.create!(plan: manifest, manifest:, evidence: storage.fetch(:evidence), dataset: expected,
                                              status: 'completed')
      end
      retained = nil
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with('/benchmark/departure-normalization-legacy.json', anything) do |_path, bytes|
        retained = JSON.parse(bytes)
        bytes.bytesize
      end
      OffseasonPerformance::LegacyDepartureNormalizationJob.perform_now(original.id)
      expect(retained).to include('status' => 'completed', 'source_count' => 4, 'player_observations' => 45,
                                  'dataset_revision' => expected.fetch('dataset_revision'))
      expect(OffseasonPerformance::LegacyDepartureNormalizationJob.new(original.id).arguments).to eq([original.id])
    end
  end
end
