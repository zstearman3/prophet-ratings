# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Reconciliation::Apply do
  include_context 'with synthetic reconciliation'

  before { game }

  it 'applies team and game selections independent of choice order and retries without writes' do
    comparison = report
    submission = decisions(comparison)
    submission['choices'].reverse!
    record = apply(comparison, submission)
    timestamps = [TeamExternalIdentity, GameExternalIdentity, IdentityMappingDecision].map { |model| model.order(:id).map(&:attributes) }
    expect(apply(comparison, submission)).to eq(record)
    expect([TeamExternalIdentity, GameExternalIdentity, IdentityMappingDecision].map { |model| model.order(:id).map(&:attributes) })
      .to eq(timestamps)
    expect(record.result['mappings'].size).to eq(3)
  end

  it 'rejects stale source or local state even after a successful request' do
    comparison = report
    apply(comparison)
    game.update!(home_team_score: 99)
    expect { apply(comparison) }.to raise_error(ArgumentError, /changed/)
    expect(IdentityMappingDecision.count).to eq(1)
  end

  it 'rejects edited artifacts and stale evidence atomically' do
    comparison = report
    comparison['coverage']['source_observations'] = 99
    expect { apply(comparison) }.to raise_error(ArgumentError, /changed/)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'rejects a conflicting team and game selection before writing an earlier valid team choice' do
    create(:team_alias, team: teams.last, value: teams.first.school)
    comparison = report
    submission = decisions(comparison)
    submission['choices'].first['local_id'] = teams.last.id
    expect { apply(comparison, submission) }.to raise_error(ArgumentError, /participant/)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'rolls back mappings if audit persistence fails' do
    comparison = report
    allow(IdentityMappingDecision).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { apply(comparison) }.to raise_error(ActiveRecord::RecordInvalid)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'requires explicit same-game supersession and retains the old identity' do
    old = GameExternalIdentity.associate!(game:, provider: 'cbbd', external_id: 'old')
    comparison = report
    submission = decisions(comparison)
    expect { apply(comparison, submission) }.to raise_error(ArgumentError, /supersession/)
    submission['choices'].last.merge!('action' => 'supersede', 'supersedes_external_id' => 'old')
    apply(comparison, submission)
    expect(old.reload).to be_superseded
    expect(GameExternalIdentity.active.find_by!(provider: 'cbbd', external_id: '1').game).to eq(game)
    expect(old.game).to eq(game)
  end

  it 'rejects duplicate, unknown and malformed choices and blank review attribution' do
    comparison = report
    submissions = [decisions(comparison).merge('reviewer' => ' '), decisions(comparison).merge('extra' => true),
                   decisions(comparison).merge('choices' => choices + [choices.first]),
                   decisions(comparison).merge('choices' => [choices.first.merge('external_id' => 'unknown')]),
                   decisions(comparison).merge('choices' => ['malformed'])]
    submissions.each { |submission| expect { apply(comparison, submission) }.to raise_error(ArgumentError) }
    expect(IdentityMappingDecision.count).to eq(0)
  end

  it 'never refreshes canonical data or observations during identity apply' do
    models = [Game, TeamGame, Prediction, TeamRatingSnapshot, GameObservation]
    before = models.map { |model| model.order(:id).map(&:attributes) }
    apply(report)
    expect(models.map { |model| model.order(:id).map(&:attributes) }).to eq(before)
  end

  it 'prevents normal audit updates and deletion' do
    record = apply(report)
    expect { record.update!(reason: 'changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rejects competing source game choices for the same local authority before writes' do
    other = observation.deep_dup.merge('source_game_id' => 2)
    replay['observations'] << other
    comparison = report
    submission = decisions(comparison)
    submission['choices'] << choices.last.merge('external_id' => '2')
    expect { apply(comparison, submission) }.to raise_error(ArgumentError, /one source game authority/)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'selects one distinct doubleheader target while preserving both canonical games' do
    first = game
    second = build(:game, season:, start_time: '2025-11-01T20:00:00Z', home_team_name: teams.first.school,
                          away_team_name: teams.last.school)
    second.save!(validate: false)
    comparison = report
    before = Game.order(:id).map(&:attributes)
    submission = decisions(comparison)
    submission['choices'].last['local_id'] = second.id
    apply(comparison, submission)
    expect(GameExternalIdentity.find_by!(external_id: '1').game_id).to eq(second.id)
    expect(Game.order(:id).map(&:attributes)).to eq(before)
    expect(Game.exists?(first.id)).to be(true)
  end

  it 'rejects corrected source evidence after mapping without changing any identity or audit record' do
    comparison = report
    apply(comparison)
    models = [TeamExternalIdentity, GameExternalIdentity, IdentityMappingDecision]
    before = models.map { |model| model.order(:id).map(&:attributes) }
    observation['home']['stats']['assists']['value'] += 1
    expect { apply(comparison) }.to raise_error(ArgumentError, /changed/)
    expect(models.map { |model| model.order(:id).map(&:attributes) }).to eq(before)
  end

  it 'preserves nonempty predictions, snapshots and observations during apply' do
    snapshot = create(:team_rating_snapshot, team_season: teams.first.team_seasons.find_by!(season:))
    create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot,
                        ratings_config_version: snapshot.ratings_config_version)
    GameObservation.create!(game:, outcome: 'synthetic', normalized_payload: observation)
    models = [Game, TeamGame, Prediction, TeamRatingSnapshot, GameObservation]
    before = models.map { |model| model.order(:id).map(&:attributes) }
    apply(report)
    expect(models.map { |model| model.order(:id).map(&:attributes) }).to eq(before)
  end
end
