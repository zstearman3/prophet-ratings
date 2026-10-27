# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/runner')

RSpec.describe OffseasonPerformance::RunVerdict do
  let(:result) do
    { 'errors' => [], 'coverage' => { 'status' => 'measured' }, 'pass' => false,
      'scenarios' => [{ 'scenario' => 'status', 'phase' => 'serial', 'failures' => ['p95 exceeds 1s'] }],
      'container_windows' => [{ 'state' => { 'OOMKilled' => false }, 'failures' => [] }] }
  end

  it 'permits only complete measured budget breaches in baseline mode' do
    expect(described_class.exit_code(result, assert: false)).to eq(0)
    expect(described_class.exit_code(result, assert: true)).to eq(1)
    result['pass'] = true
    expect(described_class.exit_code(result, assert: true)).to eq(0)
  end

  it 'fails closed in either mode on OOM, missing measurements or incomplete coverage' do
    result['container_windows'].first['state']['OOMKilled'] = true
    expect(described_class.exit_code(result, assert: false)).to eq(2)
    result['container_windows'].first['state']['OOMKilled'] = false
    result['scenarios'].first['failures'] << 'missing worker stability samples'
    expect(described_class.exit_code(result, assert: false)).to eq(2)
    result['scenarios'].first['failures'].clear
    result['coverage']['status'] = 'incomplete'
    expect(described_class.exit_code(result, assert: false)).to eq(2)
  end

  it 'requires both fresh GET phases and rejects errors even when a phase exists' do
    result['scenarios'] = [{ 'scenario' => 'preseason', 'phase' => 'serial' }]
    expect(described_class.coverage(result, ['preseason'])).to eq('preseason' => 'incomplete')
    result['scenarios'] << { 'scenario' => 'preseason', 'phase' => 'concurrent' }
    expect(described_class.coverage(result, ['preseason'])).to eq('preseason' => 'measured')
    result['scenarios'].last['error'] = 'HTTP failure'
    expect(described_class.coverage(result, ['preseason'])).to eq('preseason' => 'incomplete')
  end

  it 'requires every old/new HTTP, status, real approval, validation and first publication phase' do
    result['scenarios'] = OffseasonPerformance::DepartureValidationDriver::PHASES.map { |phase| { 'scenario' => 'departure_validation', 'phase' => phase } }
    expect(described_class.coverage(result, ['departure_validation'])).to eq('departure_validation' => 'measured')
    result['scenarios'].last['phase'] = 'validate'
    expect(described_class.coverage(result, ['departure_validation'])).to eq('departure_validation' => 'incomplete')
  end
end
