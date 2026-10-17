# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonInputs::Import do
  let(:season) { create(:season, year: 2027) }
  let!(:membership) { create(:team_season, season:, team: create(:team, school: 'Test College')) }
  let!(:other) { create(:team_season, season:) }
  let(:document) { JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read) }
  let(:batch) { capture }
  let(:paths) { { recruiting_batch_id: batch.id } }
  let(:payload) { Recruiting::DatabaseBundle.new(RecruitingBatch.find(paths.fetch(:recruiting_batch_id)), season).call }
  let(:publication) do
    { version: 'reviewed-1', reason: 'Initial evidence review', predecessor_id: nil,
      input_hash: Departures::Contract.digest(payload) }
  end
  let(:importer) { described_class.new(season:, kind: 'recruiting', paths:, publication:) }

  def capture
    bytes = JSON.generate(document)
    dataset = Recruiting::Dataset.new(bytes, 'exact saved bytes')
    RecruitingBatch.create!(season:, source_year: 2026, status: 'ready', source_status: 'ok',
                            extract_bytes: bytes, snapshot_bytes: 'exact saved bytes',
                            dataset_revision: dataset.manifest.fetch('dataset_revision'),
                            reviewed_by: 'Reviewer', reviewed_at: '2026-10-13T12:00:00Z').tap do |record|
      Recruiting::Preview.new(dataset, season).call.fetch('rows').each do |row|
        record.entries.create!(RecruitingEntry.source_attributes(row))
      end
    end
  end

  def apply
    importer.call(preview_key: importer.preview.fetch('preview_key'))
  end

  it 'previews without writes then retains decimal points, source bytes and unknown omitted teams' do
    expect { importer.preview }.not_to(change { [OffseasonInputRevision.count, TeamOffseasonProfile.count] })
    apply
    revision = OffseasonInputRevision.last
    expect(revision.team_input(membership.team_id)).to include('class_points' => '70.123456789123456789', 'status' => 'verified_points')
    expect(revision.team_input(other.team_id)).to include('class_points' => nil, 'status' => 'unknown')
    expect(Base64.strict_decode64(revision.payload.dig('evidence', 'snapshot_base64'))).to eq('exact saved bytes')
    expect(membership.team_offseason_profile.attributes.slice('recruiting_score', 'returning_minutes_pct',
                                                              'manual_adjustment').values).to all(be_nil)
  end

  it 'distinguishes reviewed explicit zero from unknown missing points' do
    document['rows'].first['class_points'] = 0
    expect(payload.dig('team_inputs', membership.team_id.to_s, 'status')).to eq('verified_zero')
    document['rows'].first.delete('class_points')
    paths[:recruiting_batch_id] = capture.id
    expect(Recruiting::DatabaseBundle.new(RecruitingBatch.find(paths.fetch(:recruiting_batch_id)), season).call
                                   .dig('team_inputs', membership.team_id.to_s, 'status')).to eq('unknown')
  end

  it 'accepts numeric source values as well as displayed decimal strings' do
    document['rows'].first['class_points'] = 65.25
    apply
    expect(OffseasonInputRevision.last.team_input(membership.team_id).fetch('class_points')).to eq('65.25')
  end

  it 'rejects changed database evidence before publication' do
    batch.update!(snapshot_bytes: 'changed after capture')
    expect { importer.preview }.to raise_error(ArgumentError, /evidence changed/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'requires a database batch rather than recruiting file paths' do
    file_import = described_class.new(season:, kind: 'recruiting', paths: {}, publication:)
    expect { file_import.preview }.to raise_error(KeyError, /recruiting_batch_id/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'makes identical retries no-ops including profile and revision timestamps' do
    apply
    before = [OffseasonInputRevision.last.attributes, TeamOffseasonProfile.order(:id).map(&:attributes)]
    apply
    expect([OffseasonInputRevision.last.attributes, TeamOffseasonProfile.order(:id).map(&:attributes)]).to eq(before)
  end

  it 'requires the reviewed input hash and rejects stale profile previews atomically' do
    report = importer.preview
    wrong = described_class.new(season:, kind: 'recruiting', paths:, publication: publication.merge(input_hash: 'wrong'))
    expect { wrong.preview }.to raise_error(ArgumentError, /INPUT_HASH/)
    create(:team_offseason_profile, team_season: membership, recruiting_score: nil, returning_minutes_pct: nil, manual_adjustment: nil)
    expect { importer.call(preview_key: report.fetch('preview_key')) }.to raise_error(ArgumentError, /fresh preview/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'requires stored reviewer and approval time' do
    batch.update!(reviewed_by: '')
    expect { importer.preview }.to raise_error(ArgumentError, /reviewer/)
    batch.update!(reviewed_by: 'Reviewer', reviewed_at: nil)
    expect { importer.preview }.to raise_error(ArgumentError, /timestamp/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'rejects malformed numeric and duplicate rows before any writes' do
    document['rows'] << document['rows'].first
    expect { importer.preview }.to raise_error(ArgumentError, /Duplicate/)
    document['rows'].pop
    document['rows'].first['class_points'] = '-1'
    paths[:recruiting_batch_id] = capture.id
    expect { importer.preview }.to raise_error(ArgumentError, /finite nonnegative/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'publishes deliberate immutable successors and never reselects old evidence on retry' do
    apply
    original = OffseasonInputRevision.last
    old_importer = importer
    batch.update!(reviewed_at: '2026-10-14T12:00:00Z')
    changed = Recruiting::DatabaseBundle.new(batch, season).call
    successor = publication.merge(version: 'reviewed-2', input_hash: Departures::Contract.digest(changed),
                                  predecessor_id: original.id, reason: 'Second evidence approval')
    described_class.new(season:, kind: 'recruiting', paths:, publication: successor)
    wrong = described_class.new(season:, kind: 'recruiting', paths:, publication: successor.merge(predecessor_id: nil))
    expect { wrong.preview }.to raise_error(ArgumentError, /PREDECESSOR_ID/)
    new_importer = described_class.new(season:, kind: 'recruiting', paths:, publication: successor)
    new_importer.call(preview_key: new_importer.preview.fetch('preview_key'))
    current = membership.reload.team_offseason_profile.recruiting_revision_id
    batch.update!(reviewed_at: '2026-10-13T12:00:00Z')
    old_importer.call(preview_key: old_importer.preview.fetch('preview_key'))
    expect(membership.reload.team_offseason_profile.recruiting_revision_id).to eq(current)
    expect(original.reload.payload).to eq(payload)
    expect { original.update!(reason: 'overwrite') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { original.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rejects revisions with unreviewed approval or changed evidence hashes' do
    attributes = { season:, kind: 'recruiting', version: 'model-test', reason: 'Reviewed input',
                   input_hash: Departures::Contract.digest(payload), dataset_hash: payload.fetch('dataset_hash'),
                   review_hash: payload.fetch('review_hash'), payload: }
    revision = OffseasonInputRevision.new(attributes)
    expect(revision).to be_valid
    revision.input_hash = 'a' * 64
    expect(revision).not_to be_valid
    expect(revision.errors[:input_hash]).to include('does not match retained evidence')
    revision.payload['review']['review_status'] = 'pending'
    revision.input_hash = Departures::Contract.digest(revision.payload)
    expect(revision).not_to be_valid
    expect(revision.errors[:payload]).to include('requires reviewed approval')
  end

  it 'rejects a profile pointer to another season or kind' do
    apply
    revision = OffseasonInputRevision.last
    profile = TeamOffseasonProfile.new(team_season: membership, departure_revision: revision)
    expect(profile).not_to be_valid
    other_membership = create(:team_season)
    profile = TeamOffseasonProfile.new(team_season: other_membership, recruiting_revision: revision)
    expect(profile).not_to be_valid
  end

  it 'rolls back the entire import when one legacy profile fails validation' do
    profile = membership.create_team_offseason_profile!
    # Reproduce an existing legacy row with absent provenance.
    profile.update_columns(recruiting_score: 1) # rubocop:disable Rails/SkipsModelValidations
    expect { apply }.to raise_error(ActiveRecord::RecordInvalid, /source reference/i)
    expect(OffseasonInputRevision.count).to eq(0)
    expect(TeamOffseasonProfile.count).to eq(1)
    expect(profile.reload.recruiting_revision_id).to be_nil
  end

  it 'preserves legacy inputs, calculations and old captures' do
    profile = create(:team_offseason_profile, team_season: membership, recruiting_score: 4)
    before = profile.attributes
    version = create(:ratings_config_version)
    prior = PreseasonPrior.create!(team_season: membership, ratings_config_version: version,
                                   inputs: { 'legacy' => 'frozen' }, outputs: { 'offense' => 100 })
    original_prior = prior.attributes
    adjustment = profile.efficiency_adjustment(ratings_config_version: version)
    apply
    expect(profile.reload.attributes.except('recruiting_revision_id',
                                            'updated_at')).to eq(before.except('recruiting_revision_id', 'updated_at'))
    expect(profile.efficiency_adjustment(ratings_config_version: version)).to eq(adjustment)
    expect(prior.reload.attributes).to eq(original_prior)
    expect(membership.team_offseason_profile.id).to eq(profile.id)
  end
end
