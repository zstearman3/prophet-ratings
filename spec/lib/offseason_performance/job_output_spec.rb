# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/job_output')
require Rails.root.join('script/performance/solver_job')

RSpec.describe OffseasonPerformance::JobOutput do
  it 'counts retained publication JSONB outputs with a scalar query and no model materialization' do
    publication = PreseasonPublication.create!(season: create(:season), reviewer: create(:user, :admin),
                                               ratings_config_version: RatingsConfigVersion.publish!, mode: 'initialize',
                                               status: 'review', fingerprint: 'synthetic', report: { 'teams' => [] })
    job = PublishPreseasonJob.new(publication.id)
    connection = ActiveRecord::Base.connection
    query = "SELECT octet_length(report::text) + octet_length(result::text) FROM preseason_publications WHERE id = #{publication.id}"
    expected = connection.select_value(query)
    allow(PreseasonPublication).to receive(:find).and_call_original
    [PreviewPreseasonJob, PublishPreseasonJob].each do |job_class|
      expect(described_class.bytes(job_class.new(publication.id))).to eq(expected)
    end
    expect(PreseasonPublication).not_to have_received(:find)
    expect(described_class.definition(job)).to include('JSONB text bytes')
  end

  it 'counts the solver result file exactly without parsing its contents' do
    allow(File).to receive(:size).with('/benchmark/solver.json').and_return(127)
    expect(described_class.bytes(OffseasonPerformance::SolverJob.new)).to eq(127)
  end

  it 'returns nil for a missing retained output in every supported database job branch' do
    [PreviewPreseasonJob, PublishPreseasonJob, RefreshScheduleJob].each do |job_class|
      expect(described_class.bytes(job_class.new(-1))).to be_nil
      expect { described_class.bytes(job_class.new('1 OR 1=1')) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects unknown jobs rather than accepting an arbitrary SQL identifier' do
    expect { described_class.bytes(ApplicationJob.new(1)) }.to raise_error(KeyError)
  end

  it 'counts an existing schedule report without loading its JSONB into a model' do
    today = Game.current_schedule_date
    season = create(:season, year: today.year + 1, start_date: today, end_date: today + 20.days)
    run = ScheduleRefreshRun.create!(season:, requested_by: create(:user, :admin), provider: 'sports_reference',
                                     start_date: today, end_date: today, report: { 'days' => [{ 'date' => today.iso8601 }] })
    expected = ActiveRecord::Base.connection.select_value(
      "SELECT octet_length(report::text) FROM schedule_refresh_runs WHERE id = #{run.id}"
    )
    allow(ScheduleRefreshRun).to receive(:find).and_call_original
    expect(described_class.bytes(RefreshScheduleJob.new(run.id))).to eq(expected)
    expect(ScheduleRefreshRun).not_to have_received(:find)
  end
end
