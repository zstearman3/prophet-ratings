# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::Contract do
  it 'retains the module identity hash for use as a Hash or Set key' do
    expect({ described_class => :contract }[described_class]).to eq(:contract)
    expect(Set[described_class]).to include(described_class)
  end
end
