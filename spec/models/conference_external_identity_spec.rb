# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConferenceExternalIdentity do
  let!(:conference) { create(:conference) }
  let(:identity) { described_class.associate!(conference:, provider: 'cbbd', external_id: '001') }

  it 'is repeatable without rewriting the mapping or conference attributes' do
    before = conference.attributes
    original = identity.attributes
    expect(described_class.associate!(conference:, provider: 'cbbd', external_id: '001').attributes).to eq(original)
    expect(conference.reload.attributes).to eq(before)
  end

  it 'rejects association to another local conference and direct ownership edits' do
    identity
    other = create(:conference)
    expect { described_class.associate!(conference: other, provider: 'cbbd', external_id: '001') }.to raise_error(described_class::Conflict)
    expect(identity.update(conference: other)).to be(false)
    expect(identity.reload.conference).to eq(conference)
  end

  it 'prevents deletion before dependent membership history can be destroyed' do
    identity
    membership = create(:team_conference, conference:)
    expect(conference.destroy).to be(false)
    expect(TeamConference.find(membership.id).attributes).to eq(membership.attributes)
  end

  it 'enforces unique provider keys in the database' do
    identity
    expect do
      described_class.connection.execute(<<~SQL.squish)
        INSERT INTO conference_external_identities (conference_id, provider, external_id, created_at, updated_at)
        VALUES (#{conference.id}, 'cbbd', '001', NOW(), NOW())
      SQL
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
