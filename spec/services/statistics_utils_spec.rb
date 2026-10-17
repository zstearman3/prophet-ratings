# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatisticsUtils do
  describe '.validate_solver_output' do
    it 'rejects missing, nonfinite, or incorrectly shaped coefficients' do
      [nil, {}, [1], [1, nil], [1, Float::NAN], [1, Float::INFINITY]].each do |values|
        expect { described_class.validate_solver_output(values, 2) }.to raise_error(ArgumentError)
      end
      expect(described_class.validate_solver_output([1, 2.5], 2)).to eq([1, 2.5])
    end
  end

  describe '.solve_least_squares_with_python' do
    it 'reports process failure before parsing partial or empty output' do
      status = instance_double(Process::Status, success?: false, exitstatus: 1, termsig: nil)
      allow(Open3).to receive(:capture3).and_return(['[1]', 'Singular matrix', status])
      expect do
        described_class.solve_least_squares_with_python([[1]], [1], ridge_alpha: 0)
      end.to raise_error(RuntimeError, /Python solver failed.*Singular matrix/)
    end
  end
end
