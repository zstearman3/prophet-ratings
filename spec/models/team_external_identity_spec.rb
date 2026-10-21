# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamExternalIdentity do
  let(:owner) { create(:team) }

  def associate(owner, provider: 'provider_a', external_id: '00042')
    described_class.associate!(team: owner, provider:, external_id:)
  end

  it 'resolves exact opaque string keys from multiple providers to the same local entity' do
    associate(owner)
    second = associate(owner, provider: 'provider_b')

    expect(second.team).to eq(owner)
    expect(described_class.find_by(provider: 'provider_a', external_id: '00042').team).to eq(owner)
    expect(described_class.find_by(provider: 'Provider_a', external_id: '00042')).to be_nil
    expect(described_class.find_by(provider: 'provider_a', external_id: '42')).to be_nil
    expect(described_class.find_by(provider: 'missing', external_id: '00042')).to be_nil
  end

  it 'returns repeated associations without updating timestamps' do
    identity = associate(owner)
    expect { associate(owner) }.not_to change(described_class, :count)
    expect(associate(owner).attributes).to eq(identity.attributes)
  end

  it 'rejects another owner without reparenting an existing identity' do
    identity = associate(owner)
    other = create(:team, school: 'Other University')

    expect { associate(other) }.to raise_error(described_class::Conflict)
    expect(identity.reload.team).to eq(owner)
    expect(described_class.count).to eq(1)
  end

  it 'rejects blank keys and missing owners' do
    [nil, '', '  '].each do |blank|
      expect(described_class.new(team: owner, provider: blank, external_id: '42')).not_to be_valid
      expect(described_class.new(team: owner, provider: 'provider_a', external_id: blank)).not_to be_valid
    end
    expect(described_class.new(provider: 'provider_a', external_id: '42')).not_to be_valid
  end

  it 'rejects changes to the provider, external key and local ownership' do
    identity = associate(owner)
    original = identity.attributes
    [{ provider: 'provider_b' }, { external_id: 'different' }, { team_id: owner.id + 1 }].each do |change|
      expect { identity.update!(change) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(identity.reload.attributes).to eq(original)
    end
  end

  it 'rejects persisted ownership and key changes under custom validation contexts' do
    identity = associate(owner)
    original = identity.attributes
    other = create(:team)
    [{ provider: 'different' }, { external_id: 'different' }, { team_id: other.id }].each do |change|
      identity.assign_attributes(change)
      expect { identity.save!(context: :reviewed_supersession) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(identity.reload.attributes).to eq(original)
    end
  end

  it 'enforces provider and external key uniqueness in the database' do
    identity = associate(owner)
    expect do
      described_class.transaction(requires_new: true) do
        described_class.new(identity.attributes.except('id')).save!(validate: false)
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'enforces the real local foreign key in the database' do
    expect do
      described_class.transaction(requires_new: true) do
        described_class.new(team_id: -1, provider: 'provider_a', external_id: '42').save!(validate: false)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'enforces required keys and local ownership in the database' do
    %i[provider external_id team_id].each do |attribute|
      expect do
        described_class.transaction(requires_new: true) do
          described_class.new(team_id: owner.id, provider: 'provider_a', external_id: '42').tap do |record|
            record[attribute] = nil
            record.save!(validate: false)
          end
        end
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  it 'restricts owner deletion before touching dependent records' do
    associate(owner)
    create(:team_alias, team: owner)
    owner.team_aliases.load
    dependent = owner.team_aliases.first
    allow(dependent).to receive(:destroy).and_call_original

    expect { owner.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(dependent).not_to have_received(:destroy)
    expect(dependent.class.find(dependent.id)).to eq(dependent)
    expect(owner.reload).to be_persisted
  end
end
