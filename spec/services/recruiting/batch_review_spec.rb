# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::BatchReview do
  let(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team, school: 'Test College') }
  let!(:other) { create(:team_season, season:) }
  let(:document) { JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read) }
  let(:batch) { capture(document) }
  let(:review) { described_class.new(batch) }

  def capture(document)
    original = JSON.generate(document)
    dataset = Recruiting::Dataset.new(original, 'exact retained source bytes')
    RecruitingBatch.create!(season:, source_year: 2026, status: 'ready', source_status: 'ok',
                            extract_bytes: original, snapshot_bytes: 'exact retained source bytes',
                            dataset_revision: dataset.manifest.fetch('dataset_revision')).tap do |record|
      Recruiting::Preview.new(dataset, season).call.fetch('rows').each do |row|
        record.entries.create!(RecruitingEntry.source_attributes(row))
      end
    end
  end

  def attributes
    { 'review_key' => review.review_key, 'confirm' => '1' }
  end

  def publish
    review.publish(attributes, reviewer: 'reviewer@example.test')
  end

  it 'publishes exact decimal points, approval and source bytes and prepares a missing TeamSeason' do
    revision = publish
    expect(batch.reload).to have_attributes(status: 'published', revision_id: revision.id, reviewed_by: 'reviewer@example.test')
    expect(revision.team_input(team.id)).to include('class_points' => '70.123456789123456789', 'status' => 'verified_points')
    expect(revision.team_input(other.team_id)).to include('class_points' => nil, 'status' => 'unknown')
    expect(Base64.strict_decode64(revision.payload.dig('evidence', 'snapshot_base64'))).to eq('exact retained source bytes')
    row = TeamSeason.find_by!(team:, season:)
    expect(row.team_offseason_profile.recruiting_revision).to eq(revision)
  end

  it 'does not populate legacy recruiting scores or recalculate existing season outputs' do
    row = create(:team_season, team:, season:, adj_pace: 72)
    publish
    expect(row.reload.adj_pace).to eq(72)
    expect(row.team_offseason_profile.recruiting_score).to be_nil
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'preserves verified zero separately from missing points' do
    document['rows'].first['class_points'] = '0'
    expect(publish.team_input(team.id)).to include('status' => 'verified_zero', 'class_points' => '0.0')
    document['rows'].first['class_points'] = nil
    missing = capture(document)
    result = described_class.new(missing).publish(
      { 'review_key' => described_class.new(missing).review_key, 'confirm' => '1' }, reviewer: 'reviewer@example.test'
    )
    expect(result.team_input(team.id)).to include('status' => 'unknown', 'class_points' => nil)
  end

  it 'stores a manual mapping and allows saving and publishing it together' do
    entry = batch.entries.sole
    values = attributes.merge('rows' => { entry.id.to_s => { 'team_id' => other.team_id.to_s } })
    result = review.publish(values, reviewer: 'reviewer@example.test')
    expect(entry.reload.team_id).to eq(other.team_id)
    expect(result.team_input(other.team_id)).to include('class_points' => '70.123456789123456789')
    expect(entry.source_label).to eq('Test College')
  end

  it 'requires explicit resolution or exclusion of unmatched rows' do
    document['rows'].first['team_label'] = 'Unmatched College'
    expect { publish }.to raise_error(ArgumentError, /Map or explicitly exclude/)
    expect(batch.reload.status).to eq('ready')
    expect(batch.reviewed_at).to be_nil
    expect(OffseasonInputRevision.count).to eq(0)
    entry = batch.entries.sole
    review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))
    expect(publish.team_input(other.team_id)).to include('status' => 'unknown')
  end

  context 'when the source has no external school identifier' do
    before do
      document['rows'].first['provider_team_id'] = nil
      document['rows'].first['team_url'] = 'https://247sports.com/season/2026-basketball/commits/'
    end

    it 'publishes the approved internal assignment without inventing an external identifier' do
      entry = batch.entries.sole
      values = attributes.merge('rows' => { entry.id.to_s => { 'team_id' => other.team_id.to_s } })

      result = review.publish(values, reviewer: 'reviewer@example.test')

      expect(batch.reload.status).to eq('published')
      expect(entry.reload.provider_team_id).to be_nil
      expect(result.team_input(other.team_id)).to include('status' => 'verified_points', 'class_points' => '70.123456789123456789')
      expect(result.payload.dig('review', 'approval', 'approved_by')).to eq('reviewer@example.test')
      expect(result.team_input(other.team_id).dig('row', 'warnings')).to include(/247Sports.*identifier/)
    end

    it 'keeps the captured bytes, source validation history and dataset fingerprint unchanged' do
      original = batch.attributes.slice('extract_bytes', 'snapshot_bytes', 'dataset_revision')
      source = batch.entries.sole.attributes.slice('source_row', 'source_errors')

      result = publish

      expect(batch.reload.attributes.slice(*original.keys)).to eq(original)
      expect(batch.entries.sole.attributes.slice(*source.keys)).to eq(source)
      expect(result.payload.dig('dataset', 'rows', 0, 'errors')).to include('provider_team_id: preserve nonempty source identity')
      expect(result.team_input(team.id).dig('row', 'raw', 'provider_team_id')).to be_nil
    end

    it 'still requires an internal assignment or an explicit exclusion' do
      document['rows'].first['team_label'] = 'Unmatched College'

      expect { publish }.to raise_error(ArgumentError, /Map or explicitly exclude/)
      expect(batch.reload.status).to eq('ready')
      expect(OffseasonInputRevision.count).to eq(0)
    end

    it 'allows explicit exclusion while keeping that school unknown' do
      entry = batch.entries.sole
      review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))

      result = publish

      expect(batch.reload.status).to eq('published')
      expect(result.team_input(other.team_id)).to include('status' => 'unknown', 'class_points' => nil)
      expect(entry.reload.source_errors).to include('provider_team_id: preserve nonempty source identity')
    end

    it 'does not treat blank external identifiers for different internal teams as duplicate identities' do
      document['rows'].first['provider_team_id'] = ''
      document['rows'] << document['rows'].first.merge('team_label' => other.team.school, 'class_points' => '12.5')

      result = publish

      expect(result.team_input(team.id)).to include('status' => 'verified_points')
      expect(result.team_input(other.team_id)).to include('status' => 'verified_points', 'class_points' => '12.5')
    end

    it 'still rejects different source rows mapped to the same internal team' do
      document['rows'] << document['rows'].first.merge('team_label' => 'Other source school')
      batch.entries.each { |entry| entry.update!(team:) }

      expect { publish }.to raise_error(ArgumentError, /Duplicate.*team_id/)
      expect(batch.reload.status).to eq('ready')
    end

    [{ 'class_points' => '-1' }, { 'team_label' => nil }, { 'team_url' => nil }, { 'provider_team_id' => 123 }].each do |invalid|
      it "still rejects invalid source #{invalid.keys.first}" do
        document['rows'].first.merge!(invalid)

        expect { publish }.to raise_error(ArgumentError, /#{invalid.keys.first}/)
        expect(OffseasonInputRevision.count).to eq(0)
      end
    end
  end

  it 'rejects stale mappings and profile changes rather than approving a different preview' do
    stale = attributes
    batch.entries.sole.update!(team: other.team)
    expect { review.publish(stale, reviewer: 'reviewer') }.to raise_error(ArgumentError, /review changed/)
    stale = attributes
    create(:team_offseason_profile, team_season: other, recruiting_score: nil, returning_minutes_pct: nil, manual_adjustment: nil)
    expect { review.publish(stale, reviewer: 'reviewer') }.to raise_error(ArgumentError, /review changed/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  context 'with an unlinked, unranked source entry' do
    before do
      document['rows'].first.merge!('team_label' => nil, 'provider_team_id' => nil, 'team_url' => nil,
                                    'rank' => '0', 'class_points' => nil)
    end

    it 'allows explicit exclusion without changing the original evidence or assigning points' do
      entry = batch.entries.sole
      original = entry.attributes.slice('source_row', 'source_errors')
      review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))

      result = publish

      expect(result.team_input(other.team_id)).to include('status' => 'unknown', 'class_points' => nil)
      expect(entry.reload.attributes.slice(*original.keys)).to eq(original)
      expect(result.payload.dig('review', 'rows', 0, 'exclusions')).to eq(['Excluded by manual review'])
    end

    it 'still rejects assigning the unranked entry to a team' do
      entry = batch.entries.sole
      review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => team.id.to_s } }))

      expect { publish }.to raise_error(ArgumentError, /rank: requires positive integer/)
    end

    it 'also allows exclusion when a new capture preserves the plain-text school name and points' do
      document['rows'].first.merge!('team_label' => 'Virginia State', 'class_points' => '23.16')
      entry = batch.entries.sole
      review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))

      result = publish

      expect(result.team_input(other.team_id)).to include('status' => 'unknown', 'class_points' => nil)
      expect(result.payload.dig('review', 'rows', 0, 'raw')).to include('team_label' => 'Virginia State', 'class_points' => '23.16')
    end

    [{ 'provider_team_id' => 123 }, { 'rank' => '0.5' }, { 'team_url' => 'https://247sports.com/college/test/' }].each do |invalid|
      it "does not extend the exclusion exception to #{invalid}" do
        document['rows'].first.merge!(invalid)
        entry = batch.entries.sole
        review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))

        expect { publish }.to raise_error(ArgumentError, /Resolve recruiting conflicts/)
      end
    end

    it 'still rejects invalid numeric values on an excluded unranked entry' do
      document['rows'].first['class_points'] = '-1'
      entry = batch.entries.sole
      review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))

      expect { publish }.to raise_error(ArgumentError, /class_points: requires finite nonnegative decimal/)
    end
  end

  it 'saves a page of known rows while leaving other decisions unchanged' do
    document['rows'] << document['rows'].first.merge('team_label' => 'Other source', 'provider_team_id' => 'other-source')
    entries = batch.entries.order(:row_number).to_a
    before = entries.last.attributes
    review.save(attributes.merge('rows' => { entries.first.id.to_s => { 'team_id' => 'excluded' } }))
    expect(entries.first.reload).to be_excluded
    expect(entries.last.reload.attributes).to eq(before)
    expect { publish }.to raise_error(ArgumentError, /Map or explicitly exclude/)
  end

  it 'requires confirmation and valid row submissions when saving mappings' do
    expect { review.publish(attributes.merge('confirm' => '0'), reviewer: 'reviewer') }.to raise_error(ArgumentError, /Confirm/)
    expect { review.save(attributes.merge('rows' => {})) }.to raise_error(ArgumentError, /known recruiting rows/)
  end

  it 'rejects invalid numeric rows and duplicate identities even if excluded' do
    document['rows'].first['class_points'] = '-1'
    expect { publish }.to raise_error(ArgumentError, /finite nonnegative decimal/)
    expect(TeamSeason.where(team:, season:)).not_to exist
    document['rows'].first['class_points'] = '1'
    document['rows'] << document['rows'].first.dup
    duplicate = capture(document)
    duplicate.entries.each { |entry| entry.update!(excluded: true, team: nil) }
    checker = described_class.new(duplicate)
    expect { checker.publish({ 'review_key' => checker.review_key, 'confirm' => '1' }, reviewer: 'reviewer') }
      .to raise_error(ArgumentError, /Duplicate/)
  end

  it 'keeps malformed legacy source rows fatal after a manual team assignment' do
    document['rows'] = [nil]
    batch.entries.sole.update!(team:)
    expect { publish }.to raise_error(ArgumentError, /Expected row object/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'detects changed normalized values and retained bytes' do
    entry = batch.entries.sole
    # rubocop:disable-next Rails/SkipsModelValidations -- simulate stored evidence corruption.
    RecruitingEntry.where(id: entry.id).update_all(class_points: 99)
    expect { review.report }.to raise_error(ArgumentError, /values changed/)
    batch.update!(snapshot_bytes: 'altered bytes')
    expect { review.report }.to raise_error(ArgumentError, /evidence changed/)
  end

  it 'makes publication retries no-ops and never rewinds a newer recruiting revision' do
    first = publish
    original = batch.reload.attributes
    document['rows'].first['class_points'] = '3.5'
    successor = capture(document)
    checker = described_class.new(successor)
    latest = checker.publish({ 'review_key' => checker.review_key, 'confirm' => '1' }, reviewer: 'reviewer')
    expect(latest.predecessor).to eq(first)
    expect(publish).to eq(first)
    expect(batch.reload.attributes).to eq(original)
    expect(other.reload.team_offseason_profile.recruiting_revision).to eq(latest)
    expect(OffseasonInputRevision.count).to eq(2)
  end

  it 'keeps a published batch closed to further mapping edits' do
    publish
    expect { review.save(attributes.merge('rows' => {})) }.to raise_error(ArgumentError, /unpublished/)
  end

  it 'rolls back review metadata, season preparation, revision and profiles on a publication failure' do
    allow(OffseasonInputs::Import).to receive(:update_profile).and_raise(ActiveRecord::RecordInvalid)
    expect { publish }.to raise_error(ActiveRecord::RecordInvalid)
    expect(batch.reload.status).to eq('ready')
    expect(batch.reviewed_by).to be_nil
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count, TeamSeason.exists?(team:, season:)]).to eq([0, 0, false])
  end

  context 'with reviewed CBBD identities' do
    let(:document) { nil }
    let(:source_rows) { [{ teamId: 72, team: team.school, year: 2026, ranking: 1, rating: 70.04 }] }
    let(:batch) do
      record = RecruitingBatch.create!(season:, source_year: 2026, extract_bytes: JSON.generate('provider' => 'cbbd'))
      body = JSON.generate(source_rows)
      transport = ->(_uri, _key) { { status: 200, body:, headers: {} } }
      Recruiting::CbbdAcquisition.new(record, api_key: 'test', transport:).call
      Recruiting::Preview.new(record.dataset, season).call.fetch('rows').each do |row|
        record.entries.create!(RecruitingEntry.source_attributes(row))
      end
      record
    end

    it 'makes durable identity win over label drift and prohibits conflicting manual assignments' do
      TeamExternalIdentity.create!(provider: 'cbbd', external_id: '72', team: other.team)
      expect(batch.entries.sole.team_id).to eq(other.team_id)
      entry = batch.entries.sole
      expect { review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => team.id.to_s } })) }
        .to raise_error(ArgumentError, /identity/)
      expect(entry.reload.team_id).to eq(other.team_id)
      expect(publish.team_input(other.team_id)).to include('class_points' => '70.04')
    end

    it 'creates durable included identities only on approval and reuses them across batches', :aggregate_failures do
      expect(batch.entries.sole.team_id).to eq(team.id)
      review.save(attributes.merge('rows' => { batch.entries.sole.id.to_s => { 'team_id' => other.team_id.to_s } }))
      expect(TeamExternalIdentity.count).to eq(0)
      revision = publish
      expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '72').team_id).to eq(other.team_id)
      expect(revision.team_input(other.team_id).dig('units', 'class_points')).to eq('cbbd_recruit_composite_class_points')
      second = RecruitingBatch.create!(season:, source_year: 2026, extract_bytes: JSON.generate('provider' => 'cbbd'))
      transport = lambda do |_uri, _key|
        { status: 200, body: '[{"teamId":72,"team":"Changed provider label","year":2026,"ranking":2,"rating":70.04}]', headers: {} }
      end
      Recruiting::CbbdAcquisition.new(second, api_key: 'test', transport:).call
      row = Recruiting::Preview.new(second.dataset, season).call.fetch('rows').sole
      second.entries.create!(RecruitingEntry.source_attributes(row))
      expect(second.entries.sole.team_id).to eq(other.team_id)
      expect(publish).to eq(revision)
    end

    it 'retains a reviewed CBBD zero and unsupported auxiliary values without inventing aggregates' do
      source_rows.first[:rating] = 0
      revision = publish
      expect(revision.team_input(team.id)).to include('class_points' => '0.0', 'status' => 'verified_zero')
      expect(batch.entries.sole).to have_attributes(average_rating: nil, commit_count: nil, source_url: nil)
    end

    it 'blocks duplicate CBBD source IDs even when every occurrence is excluded' do
      source_rows << source_rows.first.dup
      batch.entries.each { |entry| entry.update!(excluded: true, team: nil) }
      expect { publish }.to raise_error(ArgumentError, /Duplicate/)
      expect([TeamExternalIdentity.count, OffseasonInputRevision.count]).to eq([0, 0])
    end

    it 'pins absent and present identity ownership in the preview freshness token' do
      stale = attributes
      identity = TeamExternalIdentity.create!(provider: 'cbbd', external_id: '72', team:)
      expect { review.publish(stale, reviewer: 'reviewer') }.to raise_error(ArgumentError, /review changed/)
      stale = attributes
      identity.destroy!
      TeamExternalIdentity.create!(provider: 'cbbd', external_id: '72', team: other.team)
      expect { review.publish(stale, reviewer: 'reviewer') }.to raise_error(ArgumentError, /review changed/)
      expect(OffseasonInputRevision.count).to eq(0)
    end

    it 'leaves excluded identities unassigned' do
      entry = batch.entries.sole
      review.save(attributes.merge('rows' => { entry.id.to_s => { 'team_id' => 'excluded' } }))
      publish
      expect(TeamExternalIdentity.count).to eq(0)
    end

    it 'rolls back identities, review metadata, revisions and profiles when publication fails' do
      batch
      allow(OffseasonInputs::Import).to receive(:update_profile).and_raise(ActiveRecord::RecordInvalid)
      expect { publish }.to raise_error(ActiveRecord::RecordInvalid)
      expect(TeamExternalIdentity.count).to eq(0)
      expect(batch.reload.reviewed_at).to be_nil
      expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
    end

    it 'rejects conflicting ownership created during publication and rolls back the whole approval' do
      values = attributes
      allow(TeamExternalIdentity).to receive(:associate!).and_wrap_original do |method, **args|
        TeamExternalIdentity.create!(provider: 'cbbd', external_id: '72', team: other.team)
        method.call(**args)
      end
      expect { review.publish(values, reviewer: 'reviewer') }.to raise_error(TeamExternalIdentity::Conflict)
      expect(batch.reload.reviewed_at).to be_nil
      expect([OffseasonInputRevision.count, TeamOffseasonProfile.count, TeamExternalIdentity.count]).to eq([0, 0, 0])
    end
  end
end
