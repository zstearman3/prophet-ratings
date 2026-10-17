# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/release_tool/version')

RSpec.describe ReleaseTool::Version do
  let(:date) { Date.new(2026, 10, 16) }

  it 'uses a date tag first and the next numeric suffix after existing local or remote tags' do
    expect(described_class.new([], date:).choose({})).to eq('v2026.10.16')
    tags = %w[v2026.10.15 v2026.10.16 v2026.10.16.01 v2026.10.16.99 v2026.10.16.100]
    expect(described_class.new(tags, date:).choose({})).to eq('v2026.10.16.101')
    expect(described_class.new(tags, date:).choose(update: true)).to eq('v2026.10.16.100')
  end

  it 'accepts an explicit earlier draft tag and rejects invalid dates or option-like tag names' do
    version = described_class.new([], date:)
    expect(version.choose(update: true, tag: 'v2026.10.15.01')).to eq('v2026.10.15.01')
    expect { version.choose(update: true) }.to raise_error(ReleaseTool::Error, /No release tag/)
    expect { version.choose(tag: '--delete') }.to raise_error(ReleaseTool::Error, /must use/)
    expect { version.choose(tag: 'v2026.02.30') }.to raise_error(ReleaseTool::Error, /invalid date/)
  end
end
