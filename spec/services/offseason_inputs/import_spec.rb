# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe OffseasonInputs::Import do
  let(:season) { create(:season, year: 2027) }
  let!(:membership) { create(:team_season, season:, team: create(:team, school: 'Test College')) }
  let!(:other) { create(:team_season, season:) }
  let(:document) { JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read) }
  let(:directory) { Dir.mktmpdir('offseason-inputs') }
  let(:paths) { { dataset_dir: dataset_dir, review_path: File.join(directory, 'review.json') } }
  let(:dataset_dir) { Recruiting::Dataset.new(JSON.generate(document), 'exact saved bytes').save(directory) }
  let(:payload) { OffseasonInputs::RecruitingBundle.new(paths, season).call }
  let(:publication) do
    { version: 'reviewed-1', reason: 'Initial evidence review', predecessor_id: nil,
      input_hash: Departures::Contract.digest(payload) }
  end
  let(:importer) { described_class.new(season:, kind: 'recruiting', paths:, publication:) }

  before { approve }
  after { FileUtils.remove_entry(directory) }

  def approve
    report = Recruiting::Preview.new(Recruiting::Dataset.load(dataset_dir), season).call
    document = report.slice('dataset_revision', 'mapping_revision').merge('approved_by' => 'Reviewer',
                                                                          'approved_at' => '2026-10-13T12:00:00Z')
    File.write(paths.fetch(:review_path), JSON.generate(Recruiting::MappingReview.new(report).approve(document)))
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
    fresh = Recruiting::Dataset.new(JSON.generate(document), 'exact saved bytes').save(directory)
    paths[:dataset_dir] = fresh
    allow(self).to receive(:dataset_dir).and_return(fresh)
    approve
    expect(payload.dig('team_inputs', membership.team_id.to_s, 'status')).to eq('verified_zero')
    document['rows'].first.delete('class_points')
    fresh = Recruiting::Dataset.new(JSON.generate(document), 'exact saved bytes').save(directory)
    paths[:dataset_dir] = fresh
    allow(self).to receive(:dataset_dir).and_return(fresh)
    approve
    expect(OffseasonInputs::RecruitingBundle.new(paths, season).call.dig('team_inputs', membership.team_id.to_s, 'status')).to eq('unknown')
  end

  it 'accepts JSON decimal numbers as well as displayed decimal strings after mapping-file serialization' do
    document['rows'].first['class_points'] = 65.25
    fresh = Recruiting::Dataset.new(JSON.generate(document), 'exact saved bytes').save(directory)
    paths[:dataset_dir] = fresh
    allow(self).to receive(:dataset_dir).and_return(fresh)
    approve
    apply
    expect(OffseasonInputRevision.last.team_input(membership.team_id).fetch('class_points')).to eq('65.25')
  end

  it 'rejects source bytes changed between validation and retention' do
    bundle = OffseasonInputs::RecruitingBundle.new(paths, season)
    File.write(File.join(dataset_dir, 'snapshot'), 'changed after validation')
    expect { bundle.call }.to raise_error(ArgumentError, /evidence changed/)
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

  it 'rejects absent, stale or tampered approval and conflicting mappings' do
    review = JSON.parse(File.read(paths.fetch(:review_path)))
    review['approval']['approved_by'] = ''
    File.write(paths.fetch(:review_path), JSON.generate(review))
    expect { importer.preview }.to raise_error(ArgumentError, /approved_by/)
    approve
    review = JSON.parse(File.read(paths.fetch(:review_path)))
    review['rows'].first['team_id'] = other.team_id
    File.write(paths.fetch(:review_path), JSON.generate(review))
    expect { importer.preview }.to raise_error(ArgumentError, /report changed/)
    approve
    create(:team_alias, team: other.team, source: '247sports', value: 'Test College')
    expect { importer.preview }.to raise_error(ArgumentError, /Ambiguous/)
  end

  it 'rejects malformed numeric and duplicate rows before any writes' do
    document['rows'] << document['rows'].first
    fresh = Recruiting::Dataset.new(JSON.generate(document), 'exact saved bytes').save(directory)
    paths[:dataset_dir] = fresh
    allow(self).to receive(:dataset_dir).and_return(fresh)
    approve
    expect { importer.preview }.to raise_error(ArgumentError, /Duplicate/)
    document['rows'].pop
    document['rows'].first['class_points'] = '-1'
    fresh = Recruiting::Dataset.new(JSON.generate(document), 'exact saved bytes').save(directory)
    paths[:dataset_dir] = fresh
    allow(self).to receive(:dataset_dir).and_return(fresh)
    approve
    expect { importer.preview }.to raise_error(ArgumentError, /finite nonnegative/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'publishes deliberate immutable successors and never reselects old evidence on retry' do
    apply
    original = OffseasonInputRevision.last
    old_importer = importer
    review = JSON.parse(File.read(paths.fetch(:review_path)))
    review['approval']['approved_at'] = '2026-10-14T12:00:00Z'
    File.write(paths.fetch(:review_path), JSON.generate(review))
    changed = OffseasonInputs::RecruitingBundle.new(paths, season).call
    successor = publication.merge(version: 'reviewed-2', input_hash: Departures::Contract.digest(changed),
                                  predecessor_id: original.id, reason: 'Second evidence approval')
    described_class.new(season:, kind: 'recruiting', paths:, publication: successor)
    wrong = described_class.new(season:, kind: 'recruiting', paths:, publication: successor.merge(predecessor_id: nil))
    expect { wrong.preview }.to raise_error(ArgumentError, /PREDECESSOR_ID/)
    new_importer = described_class.new(season:, kind: 'recruiting', paths:, publication: successor)
    new_importer.call(preview_key: new_importer.preview.fetch('preview_key'))
    current = membership.reload.team_offseason_profile.recruiting_revision_id
    review['approval']['approved_at'] = '2026-10-13T12:00:00Z'
    File.write(paths.fetch(:review_path), JSON.generate(review))
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
