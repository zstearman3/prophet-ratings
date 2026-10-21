# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameObservation do
  it 'preserves accepted and rejected evidence as immutable records' do
    record = described_class.create!(outcome: 'invalid', reason: 'synthetic rejection', raw_payload: { points: nil })
    expect { record.update!(outcome: 'final') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.reload.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(record.reload).to have_attributes(outcome: 'invalid', reason: 'synthetic rejection', accepted: false)
  end
end
