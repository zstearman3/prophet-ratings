# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameExternalIdentity do
  let(:owner) { create(:game) }

  def associate(owner, provider: 'provider_a', external_id: '00042')
    described_class.associate!(game: owner, provider:, external_id:)
  end

  it 'resolves exact opaque string keys from multiple providers to the same local entity' do
    associate(owner)
    second = associate(owner, provider: 'provider_b')

    expect(second.game).to eq(owner)
    expect(described_class.find_by(provider: 'provider_a', external_id: '00042').game).to eq(owner)
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
    other = create(:game, season: owner.season, start_time: 1.day.from_now)

    expect { associate(other) }.to raise_error(described_class::Conflict)
    expect(identity.reload.game).to eq(owner)
    expect(described_class.count).to eq(1)
  end

  it 'rejects blank keys and missing owners' do
    [nil, '', '  '].each do |blank|
      expect(described_class.new(game: owner, provider: blank, external_id: '42')).not_to be_valid
      expect(described_class.new(game: owner, provider: 'provider_a', external_id: blank)).not_to be_valid
    end
    expect(described_class.new(provider: 'provider_a', external_id: '42')).not_to be_valid
  end

  it 'rejects changes to the provider, external key and local ownership' do
    identity = associate(owner)
    original = identity.attributes
    [{ provider: 'provider_b' }, { external_id: 'different' }, { game_id: owner.id + 1 }].each do |change|
      expect { identity.update!(change) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(identity.reload.attributes).to eq(original)
    end
  end

  it 'rejects persisted ownership and key changes under custom validation contexts' do
    identity = associate(owner)
    original = identity.attributes
    other = create(:game, season: owner.season, start_time: 1.day.from_now)
    [{ provider: 'different' }, { external_id: 'different' }, { game_id: other.id }].each do |change|
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
        described_class.new(game_id: -1, provider: 'provider_a', external_id: '42').save!(validate: false)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'enforces required keys and local ownership in the database' do
    %i[provider external_id game_id].each do |attribute|
      expect do
        described_class.transaction(requires_new: true) do
          described_class.new(game_id: owner.id, provider: 'provider_a', external_id: '42').tap do |record|
            record[attribute] = nil
            record.save!(validate: false)
          end
        end
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe 'reviewed source replacement' do
    let!(:original) { associate(owner) }

    it 'rejects a second active source for the same provider and game in the database' do
      expect do
        described_class.transaction(requires_new: true) do
          described_class.new(game_id: owner.id, provider: 'provider_a', external_id: 'other').save!(validate: false)
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
      expect { associate(owner, external_id: 'other') }.to raise_error(described_class::Conflict)
    end

    it 'retains old mappings and supports chains without changing the local game' do
      replacement = original.supersede!(external_id: 'replacement')
      latest = replacement.supersede!(external_id: 'latest')

      expect(original.reload).to be_superseded
      expect(latest).not_to be_superseded
      expect(described_class.active).to eq([latest])
      expect(described_class.find_by(provider: 'provider_a', external_id: '00042').game).to eq(owner)
      expect(described_class.pluck(:game_id).uniq).to eq([owner.id])
    end

    it 'rechecks separately loaded stale instances and permits only the current identical retry' do
      stale = described_class.find(original.id)
      replacement = original.supersede!(external_id: 'replacement')

      expect(stale.supersede!(external_id: 'replacement')).to eq(replacement)
      expect { stale.supersede!(external_id: 'different') }.to raise_error(described_class::Conflict)
      replacement.supersede!(external_id: 'latest')
      expect { stale.supersede!(external_id: 'replacement') }.to raise_error(described_class::Conflict)
      expect(described_class.active.pluck(:external_id)).to eq(['latest'])
    end

    it 'never reactivates a superseded identity during repeated association' do
      original.supersede!(external_id: 'replacement')
      expect(associate(owner)).to be_superseded
      expect(described_class.active.pluck(:external_id)).to eq(['replacement'])
    end

    it 'treats a same-key request as a no-op' do
      expect(original.supersede!(external_id: '00042')).to eq(original)
      expect(original.reload).not_to be_superseded
      expect(described_class.count).to eq(1)
    end

    it 'rejects direct retirement and reactivation through normal model writes' do
      expect { original.update!(superseded_at: Time.current) }.to raise_error(ActiveRecord::RecordInvalid)
      original.reload.supersede!(external_id: 'replacement')
      expect { original.reload.update!(superseded_at: nil) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(original.reload).to be_superseded
    end

    it 'rejects custom-context reactivation even without an active identity collision' do
      retired = described_class.create!(game: owner, provider: 'provider_b', external_id: 'retired', superseded_at: 1.day.ago)
      retired.superseded_at = nil

      expect { retired.save!(context: :reviewed_supersession) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(retired.reload).to be_superseded
      expect(described_class.active.where(provider: 'provider_b')).to be_empty
    end

    it 'rolls back invalid replacements even when an outer transaction rescues the error' do
      described_class.transaction do
        expect { original.supersede!(external_id: ' ') }.to raise_error(ActiveRecord::RecordInvalid)
        expect(original.reload).not_to be_superseded
        expect(described_class.count).to eq(1)
      end
    end

    it 'rolls back retirement when the replacement belongs to another game' do
      other_game = create(:game, season: owner.season, start_time: 1.day.from_now)
      target = associate(other_game, external_id: 'taken')
      expect { original.supersede!(external_id: 'taken') }.to raise_error(described_class::Conflict)
      expect(original.reload).not_to be_superseded
      expect(target.reload.game).to eq(other_game)
      expect(described_class.count).to eq(2)
    end

    it 'rejects a retired replacement target without reactivating it' do
      replacement = original.supersede!(external_id: 'replacement')
      expect { replacement.supersede!(external_id: '00042') }.to raise_error(described_class::Conflict)
      expect(replacement.reload).not_to be_superseded
      expect(original.reload).to be_superseded
    end

    it 'rolls back retirement on a persistence failure' do
      allow(described_class).to receive(:create_or_find_by!).and_raise(ActiveRecord::StatementInvalid, 'write failed')
      expect { original.supersede!(external_id: 'replacement') }.to raise_error(ActiveRecord::StatementInvalid, 'write failed')
      expect(original.reload).not_to be_superseded
      expect(described_class.count).to eq(1)
    end
  end

  it 'restricts owner deletion before touching dependent records' do
    associate(owner)
    team = create(:team)
    dependent = create(:team_game, game: owner, team:, team_season: create(:team_season, team:, season: owner.season))
    owner.away_team_game = dependent
    allow(dependent).to receive(:destroy).and_call_original

    expect { owner.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(dependent).not_to have_received(:destroy)
    expect(dependent.class.find(dependent.id)).to eq(dependent)
    expect(owner.reload).to be_persisted
  end

  it 'preserves existing local records, relationships, odds IDs and manual corrections' do
    team = create(:team, the_odds_api_team_id: 'existing-odds-key')
    team_season = create(:team_season, team:, season: owner.season)
    create(:team_alias, team:, value: 'Existing label')
    create(:team_game, game: owner, team:, team_season:)
    owner.update!(venue_type: 'neutral', venue_confidence: 'manual', venue_source: 'manual_override', venue_name: 'Reviewed venue')
    version = RatingsConfigVersion.ensure_current!
    home = create(:team_rating_snapshot, team_season:, ratings_config_version: version)
    away = create(:team_rating_snapshot, team_season: create(:team_season, season: owner.season), ratings_config_version: version)
    create(:prediction, game: owner, home_team_snapshot: home, away_team_snapshot: away, ratings_config_version: version)
    models = [Game, Team, TeamGame, TeamAlias, Prediction, TeamSeason, TeamRatingSnapshot]
    before_records = models.index_with { |model| model.order(:id).map(&:attributes) }

    %w[provider_a provider_b].each do |provider|
      associate(owner, provider:)
      TeamExternalIdentity.associate!(team:, provider:, external_id: '00042')
    end

    expect(models.index_with { |model| model.order(:id).map(&:attributes) }).to eq(before_records)
  end

  it 'offers a nonraising replacement interface for review tools' do
    identity = associate(owner)
    expect(identity.supersede(external_id: ' ')).to be(false)
    expect(identity.reload).not_to be_superseded
    expect(identity.supersede(external_id: 'replacement')).to be_a(described_class)
    expect(identity.reload.supersede(external_id: 'different')).to be(false)
  end
end
