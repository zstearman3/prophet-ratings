# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/phase_queue')

RSpec.describe OffseasonPerformance::PhaseQueue do
  it 'routes ActiveJob and GoodJob to exactly the current phase, retaining interrupted prior jobs' do
    owner = 'offseason-abcdef'
    prior = GoodJob::Job.create!(queue_name: described_class.name(owner, 'publish-serial'),
                                 serialized_params: {}, performed_at: Time.current)
    current = GoodJob::Job.create!(queue_name: described_class.name(owner, 'schedule-serial'), serialized_params: {})
    job_class = Class.new(ApplicationJob)
    job_class.queue_name_prefix = described_class.prefix(owner, 'schedule-serial')
    job_class.queue_as :default
    queue = job_class.new.queue_name
    expect(queue).to eq('offseason-abcdef_schedule-serial_default')
    pools = "#{described_class.name(owner, 'schedule-serial', 'heavy')}:1;#{queue}:1"
    expect(described_class.worker_arguments(owner, 'schedule-serial'))
      .to eq(['start', '--max-threads=1', '--subprocesses=0', "--queues=#{pools}"])
    expect(GoodJob::Job.unfinished.queue_string(queue).pluck(:id)).to eq([current.id])
    expect(GoodJob::Job.exists?(prior.id)).to be(true)
  end

  it 'rejects wildcard or invalid queue selectors' do
    expect { described_class.name('offseason-abcdef', '*') }.to raise_error(ArgumentError)
    expect { described_class.name('other', 'setup') }.to raise_error(ArgumentError)
  end
end
