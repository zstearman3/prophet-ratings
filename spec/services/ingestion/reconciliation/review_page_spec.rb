# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Reconciliation::ReviewPage do
  let(:rows) do
    Array.new(53) do |index|
      { 'external_id' => "source-#{index}", 'names' => ["Synthetic School #{index}"], 'status' => index.even? ? 'proposed' : 'conflicting' }
    end
  end
  let(:comparison) { CbbdReviewComparison.new(report: { 'teams' => rows, 'games' => [] }) }

  let(:literal_row) do
    { 'names' => ['Texas A&M', 'William & Mary'], 'status' => 'proposed',
      'key_only_token' => [{ 'evidence' => 'Literal <home> vs >away<', 'source_id' => '0012',
                             'raw' => 0, 'availability' => 'unknown', 'nested' => [['nested leaf']] }] }
  end
  let(:literal_report) { { 'teams' => [literal_row] } }

  it 'paginates at fifty rows and retains the total denominator' do
    first = described_class.new(comparison.report, {})
    last = described_class.new(comparison.report, { 'page' => '2' })
    expect([first.rows.size, first.pages, first.total]).to eq([50, 2, 53])
    expect(last.rows.pluck('external_id')).to eq(%w[source-50 source-51 source-52])
  end

  it 'filters status and case-insensitive names or opaque IDs before pagination' do
    page = described_class.new(comparison.report, { 'q' => 'SCHOOL 5', 'status' => 'proposed' })
    expect([page.matched, page.total]).to eq([2, 53])
    expect(page.rows.pluck('external_id')).to eq(%w[source-50 source-52])
    expect(described_class.new(comparison.report, { 'q' => 'source-01' }).matched).to eq(0)
  end

  it 'paginates and filters shadow categories without treating them as approval rows' do
    mismatches = Array.new(53) { |index| { 'local_game_id' => index, 'category' => 'semantics', 'field' => 'turnovers' } }
    report = { 'shadow' => { 'mismatches' => mismatches } }
    page = described_class.new(report, { 'entity' => 'shadow', 'status' => 'semantics', 'q' => 'TURNOVERS', 'page' => '2' })
    expect([page.total, page.rows.size, page.rows.first['local_game_id']]).to eq([53, 3, 50])
    expect(described_class.new(report, { 'entity' => 'shadow', 'status' => 'likely_local_defect' }).matched).to eq(0)
  end

  it 'rejects bulk rows outside the server-computed visible page' do
    report = comparison.report
    row = { 'entity' => 'team', 'external_id' => 'source-52' }
    submission = { 'rows' => [row], 'filters' => {} }
    expect { Ingestion::Reconciliation::BulkApproval.new(report, {}, submission).call }.to raise_error(ArgumentError, /visible/)
  end

  it 'searches literal nested evidence values, opaque IDs, zero and unknown availability case-insensitively' do
    ['TEXAS A&M', 'William & Mary', '<home>', '>away<', '0012', '0', 'UNKNOWN', 'NESTED LEAF'].each do |query|
      page = described_class.new(literal_report, { 'q' => query, 'status' => 'proposed' })
      expect(page.rows).to eq([literal_row]), "Expected literal evidence query #{query.inspect} to match"
    end
  end

  it 'does not search hash keys and keeps blank search inclusive' do
    expect(described_class.new(literal_report, { 'q' => 'key_only_token' }).matched).to eq(0)
    expect(described_class.new(literal_report, { 'q' => 'names' }).matched).to eq(0)
    expect(described_class.new(literal_report, { 'q' => '' }).rows).to eq([literal_row])
    expect(described_class.new(literal_report, {}).rows).to eq([literal_row])
  end
end
