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
    expect { run.create_retry!(attributes[:requested_by]) }.to raise_error(ArgumentError, /terminal/)
    run.update!(status: 'incomplete', report: { days: [{ date: today.to_s }, { date: (today + 1.day).to_s, error: 'failed' }] })
    retry_run = run.create_retry!(attributes[:requested_by])
    expect(retry_run.requested_dates).to eq([(today + 1.day).to_s, (today + 2.days).to_s])
    expect(retry_run).to be_persisted
    expect(retry_run.retry_of).to eq(run)
  end

  it 'rejects repeated parent retries after a child exists, including a previously cached missing child' do
    run = described_class.create!(attributes.merge(status: 'incomplete'))
    expect(run.retry_run).to be_nil
    child = described_class.find(run.id).create_retry!(attributes[:requested_by])
    original = run.attributes.deep_dup
    %w[queued running succeeded incomplete failed].each do |status|
      child.update!(status:)
      expect { run.create_retry!(attributes[:requested_by]) }.to raise_error(ArgumentError, /already exists/)
    end
    expect(described_class.where(retry_of: run).pluck(:id)).to eq([child.id])
    expect(run.reload.attributes).to eq(original)
  end

  it 'preserves root reports and budgets while allowing unfinished leaf retries to form a chain' do
    root = described_class.create!(attributes.merge(provider: 'cbbd', max_requests: 4, retries: 1, status: 'incomplete',
                                                    report: { days: [{ date: today.to_s }] }))
    child = root.create_retry!(attributes[:requested_by])
    child.update!(status: 'failed')
    leaf = child.create_retry!(attributes[:requested_by])
    aggregate_failures do
      expect([leaf.retry_of_id, child.retry_of_id]).to eq([child.id, root.id])
      expect(leaf.attributes.values_at('provider', 'max_requests', 'retries')).to eq(['cbbd', 4, 1])
      expect(leaf.requested_dates).to eq([(today + 1.day).to_s, (today + 2.days).to_s])
      expect(root.reload.report).to eq('days' => [{ 'date' => today.to_s }])
    end
  end

  it 'enforces one immediate retry parent in PostgreSQL while permitting multiple roots and a chain' do
    root = described_class.create!(attributes)
    another_root = described_class.create!(attributes)
    child = described_class.create!(attributes.merge(retry_of: root))
    leaf = described_class.create!(attributes.merge(retry_of: child))
    expect do
      described_class.transaction(requires_new: true) { described_class.create!(attributes.merge(retry_of: root)) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.where(retry_of_id: nil).pluck(:id)).to contain_exactly(root.id, another_root.id)
    expect(leaf.retry_of).to eq(child)
  end

  it 'returns invalid unsaved records from the nonbang creator and raises from the bang creator without persisting either' do
    run = described_class.create!(attributes.merge(status: 'incomplete'))
    allow(Game).to receive(:current_schedule_date).and_return(today + 3.days)
    child = run.create_retry(attributes[:requested_by])
    expect(child).not_to be_persisted
    expect(child.errors.full_messages.join).to include('historical sync')
    expect { run.create_retry!(attributes[:requested_by]) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(described_class.where(retry_of: run)).to be_empty
  end

  it 'retains fixed numeric CBBD budgets and refuses later scope edits' do
    run = described_class.create!(attributes.merge(provider: 'cbbd', max_requests: 4, retries: 1))
    expect { run.update!(max_requests: 8) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
