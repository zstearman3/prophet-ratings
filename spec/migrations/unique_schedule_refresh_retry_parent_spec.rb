# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261022030000_unique_schedule_refresh_retry_parent')

RSpec.describe UniqueScheduleRefreshRetryParent do
  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:attributes) do
    { season:, requested_by: create(:user, :admin), provider: 'sports_reference', start_date: today.to_s, end_date: today.to_s }
  end

  before { allow(Game).to receive(:current_schedule_date).and_return(today) }

  def retry_index
    ActiveRecord::Base.connection.indexes(:schedule_refresh_runs).find { |index| index.columns == ['retry_of_id'] }
  end

  it 'rolls duplicate-history migration failure back with the original index and every run unchanged' do
    migration = described_class.new
    migration.migrate(:down)
    parent = ScheduleRefreshRun.create!(attributes)
    2.times { ScheduleRefreshRun.create!(attributes.merge(retry_of: parent)) }
    original = ScheduleRefreshRun.order(:id).map(&:attributes)
    original_index = retry_index
    expect do
      ScheduleRefreshRun.transaction(requires_new: true) { migration.migrate(:up) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
    aggregate_failures do
      expect(ScheduleRefreshRun.order(:id).map(&:attributes)).to eq(original)
      expect(retry_index.name).to eq(original_index.name)
      expect(retry_index.unique).to be(false)
    end
    # The fixture transaction restores the schema and scoped synthetic rows afterward.
  end

  it 'restores the unique index through an explicit down/up round trip' do
    migration = described_class.new
    migration.migrate(:down)
    expect(retry_index.unique).to be(false)
    migration.migrate(:up)
    expect(retry_index.unique).to be(true)
  end
end
