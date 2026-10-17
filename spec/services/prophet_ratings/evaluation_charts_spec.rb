# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::EvaluationCharts do
  let(:chart_class) do
    Class.new do
      attr_accessor :labels

      def data(*); end
    end
  end
  let(:chart) { instance_double(chart_class) }

  before do
    stub_const('Gruff::Line', chart_class)
    allow(chart_class).to receive(:new).and_return(chart)
    allow(chart).to receive(:labels=)
    allow(chart).to receive(:data)
  end

  it 'uses contiguous labels, all sample counts, and mean predicted probabilities for PNG calibration' do
    bins = [{ lower: 0.1, games: 1, mean_probability: 0.13, observed_home_win_rate: 0 },
            { lower: 0.9, games: 12, mean_probability: 0.96, observed_home_win_rate: 1 }]
    described_class.calibration_chart(bins)
    expect(chart).to have_received(:labels=).with(0 => '0.1 (n=1)', 1 => '0.9 (n=12)')
    expect(chart).to have_received(:data).with('Mean predicted probability', [0.13, 0.96])
    expect(chart).to have_received(:data).with('Observed win rate', [0, 1])
  end
end
