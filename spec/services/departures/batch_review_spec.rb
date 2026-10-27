# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::BatchReview do
  let(:season) { create(:season, year: 2026) }
  let(:attributes) do
    { 'draft_year' => '2025', 'prior_season_year' => '2025', 'target_year' => '2026', 'expected_picks' => (1..60).to_a.join(' '),
      'sources' => { '0' => { 'type' => 'nba_results', 'url' => 'https://www.nba.com/news/2025-nba-draft-order' } } }
  end

  before { create(:team_season, season:) }

  context 'with retained review and publication' do
    let(:team) { create(:team, school: 'Sample School') }
    let(:other) { create(:team, school: 'Other School') }
    let(:batch) { legacy_departure_batch(season) }

    before do
      create(:team_season, season:, team:)
      create(:team_season, season:, team: other)
      capture_departures(batch)
    end

    it 'replays retained evidence once for a report' do
      review = described_class.new(batch)
      allow(Departures::AnnualDataset).to receive(:new).and_call_original
      expect(review.report.fetch('errors')).to eq([])
      expect(Departures::AnnualDataset).to have_received(:new).once
    end

    it 'keeps a reused review fresh after new captures and preparation edits' do
      review = described_class.new(batch)
      old_dataset = review.dataset
      old_key = review.review_key
      capture_departures(batch)
      expect(review.dataset).to eq(batch.attempt.dataset)
      expect(review.dataset).not_to eq(old_dataset)
      expect { review.save('review_key' => old_key, 'rows' => departure_rows(team)) }.to raise_error(ArgumentError, /changed/)
      capture_departures(batch)
      review.save('review_key' => review.review_key, 'rows' => departure_rows(team))
      revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin@example.com')
      expect(revision.dataset_hash).to eq(batch.attempt.dataset.fetch('dataset_revision'))
    end

    it 'replays again when saving and publishing after an earlier report' do
      review = described_class.new(batch)
      review.report
      allow(Departures::AnnualDataset).to receive(:new).and_call_original
      review.save('review_key' => review.review_key, 'rows' => departure_rows(team))
      expect(Departures::AnnualDataset).to have_received(:new).once
      allow(Departures::AnnualDataset).to receive(:new).and_call_original
      revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin@example.com')
      expect(revision.team_input(team.id)['loss_share']).to eq(0.25)
      expect(Departures::AnnualDataset).to have_received(:new).at_least(:twice)
    end

    it 'publishes hand-calculated production and verified zero with authenticated approval and no model writes' do
      save_departure_rows(batch, departure_rows(team))
      allow(HTTParty).to receive(:get).and_raise('Unexpected HTTP during retained evidence review')
      revision = approve_departures(batch)
      expect(revision.team_input(team.id)).to include('loss_share' => 0.25, 'known_points_subtotal' => 500)
      expect(revision.team_input(other.id)).to include('loss_share' => 0.0, 'reason' => 'verified_zero')
      expect([revision.payload.dig('review', 'reviewed_by'),
              revision.payload.dig('report', 'selections').last['stints'].first['player_points']]).to eq(['admin@example.com', 0])
      expect([TeamRatingSnapshot.count, PreseasonPrior.count, season.reload.current?]).to eq([0, 0, false])
      expect { batch.reload.update!(decisions: []) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'retains actual partial gaps, invalidates stale forms and never acknowledges hard conflicts' do
      rows = departure_rows(team).except('2025/60')
      review = save_departure_rows(batch, rows)
      expect { approve_departures(batch) }.to raise_error(ArgumentError, /Acknowledge/)
      key = review.review_key
      create(:team_alias, team:, value: 'Changed', source: 'school.example')
      expect { review.publish({ 'review_key' => key, 'confirm' => '1', 'acknowledge_gaps' => '1' }, reviewer: 'admin') }
        .to raise_error(ArgumentError, /changed/)
      revision = approve_departures(batch, 'acknowledge_gaps' => '1')
      expect(revision.payload.dig('review', 'partial_acknowledgement', 'gaps')).to include('Selection 2025/60: unknown_participation')
      correction = Departures::BatchPreparation.new(batch.reload).correct('Resolve missing selection')
      rows['2025/60'] = { 'status' => 'conflicting_evidence', 'reason' => 'Contradiction', 'evidence_source_ids' => ['source-1'] }
      save_departure_rows(correction, rows)
      expect { approve_departures(correction, 'acknowledge_gaps' => '1') }.to raise_error(ArgumentError, /conflicting/)
      expect([OffseasonInputRevision.count, correction.reload.reviewed_by]).to eq([1, nil])
    end

    it 'creates correction successors and retries an old approval without rewinding profile pointers' do
      save_departure_rows(batch, departure_rows(team))
      first = approve_departures(batch)
      correction = Departures::BatchPreparation.new(batch.reload).correct('Review correction')
      expect(correction.acknowledgement).to eq({})
      second = approve_departures(correction)
      expect(second.predecessor_id).to eq(first.id)
      expect(approve_departures(batch).id).to eq(first.id)
      expect(TeamOffseasonProfile.distinct.pluck(:departure_revision_id)).to eq([second.id])
      expect(correction.attempt.predecessor_id).to eq(batch.attempt.id)
    end

    it 'keeps uniquely identified unknown production local and rejects forged player/source identities' do
      rows = departure_rows(team)
      rows['2025/60'] = { 'status' => 'unknown_production', 'reason' => 'Unestablished totals',
                          'team_id' => team.id.to_s, 'evidence_source_ids' => ['source-1'] }
      review = save_departure_rows(batch, rows)
      expect(review.report.fetch('teams').find { |row| row['team_id'] == team.id }['loss_share']).to be_nil
      expect(review.report.fetch('teams').find { |row| row['team_id'] == other.id }['loss_share']).to eq(0.0)
      rows['2025/1']['stints']['0']['production_key'] = 'forged'
      expect { save_departure_rows(batch, rows) }.to raise_error(ArgumentError, /Unknown captured/)
    end

    it 'rolls back approval and pointers when publication fails' do
      save_departure_rows(batch, departure_rows(team))
      allow(OffseasonInputs::Import).to receive(:update_profile).and_raise('Synthetic publication failure')
      expect { approve_departures(batch) }.to raise_error('Synthetic publication failure')
      expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
      expect(batch.reload.reviewed_by).to be_nil
    end
  end

  it 'retains blocked bytes, recovers without network and preserves both immutable attempts' do
    batch = legacy_departure_batch(season, attributes)
    attempt = capture_departures(batch, body: 'Blocked original bytes', status: 403)
    expect(attempt.reload.status).to eq('incomplete')
    expect(Departures::RetainedEvidence.new(attempt).bytes('source-1')).to eq('Blocked original bytes')
    allow(HTTParty).to receive(:get).and_raise('Unexpected HTTP during retained evidence review')
    recovery = { 'source_id' => 'source-1', 'url' => attributes.dig('sources', '0', 'url'), 'http_status' => '200',
                 'captured_at' => '2026-10-21T10:00:00Z', 'observed_at' => '2026-10-21T10:01:00Z',
                 'source_as_of_reason' => 'Unavailable',
                 'html' => StringIO.new(Rails.root.join('spec/fixtures/departures/draft.html').read) }
    successor = Departures::BatchAcquisition.new(attempt).recover(recovery)
    expect([successor.status, successor.predecessor_id, attempt.reload.manifest.dig('sources', 0, 'http_status')])
      .to eq(['completed', attempt.id, 403])
    expect { attempt.update!(failure: 'Relabelled') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects new legacy acquisitions before HTTP while preserving historical evidence' do
    batch = legacy_departure_batch(season)
    attempt = capture_departures(batch)
    expect { Departures::BatchPreparation.new(batch).acquire }.to raise_error(ArgumentError)
    expect(Departures::RetainedEvidence.new(attempt).dataset).to eq(attempt.dataset)
  end

  it 'never treats absent target memberships as a prepared season' do
    empty = create(:season, year: 2027)
    fields = cbbd_fields.merge('draft_year' => '2026', 'prior_season_year' => '2026', 'target_year' => '2027')
    expect { Departures::BatchPreparation.create(empty, fields) }.to raise_error(ArgumentError, /memberships/)
  end

  it 'keeps progress honest for acquisition states, publication, stale identities and later failures', :aggregate_failures do
    team = create(:team, school: 'Sample School')
    create(:team_season, season:, team:)
    batch = legacy_departure_batch(season)
    attempt = capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    revision = approve_departures(batch)
    expect(DepartureProgress.new(season).call.status).to eq('needs_review')
    operation = Departures::ValidationPreparation.create(batch.reload)
    Departures::ValidationPreparation.new(operation).call
    expect(operation.reload.status).to eq('ready'), operation.error
    expect(DepartureProgress.new(season).call.status).to eq('complete')
    team.update!(school: 'Changed canonical identity')
    expect(DepartureProgress.new(season).call.status).to eq('needs_review')
    team.update!(school: 'Sample School')
    correction = Departures::BatchPreparation.new(batch.reload).correct('Source follow-up')
    correction.update!(plan: Departures::PreparationForm.new(cbbd_fields, season).call)
    next_attempt = Departures::BatchPreparation.new(correction).acquire
    %w[queued running failed].each do |state|
      next_attempt.update!(status: state)
      progress = DepartureProgress.new(season).call
      expect([progress.status, progress.last_result]).to eq(
        ['needs_review',
         "Departure revision ##{revision.id} is retained. Latest departure batch ##{correction.id}: draft; " \
         "acquisition #{state}; validation needed."]
      )
    end
    expect(attempt.reload.status).to eq('completed')
  end

  it 'supports multiple prior-season stints without accepting numeric form facts' do
    team = create(:team, school: 'Sample School')
    second = create(:team, school: 'Second School')
    fields = departure_fields
    fields['sources']['2'] =
      fields['sources']['1'].merge('url' => 'https://second.example/stats/2024-25', 'team_name_source' => second.school)
    batch = legacy_departure_batch(season, fields)
    capture_departures(batch)
    rows = departure_rows(team)
    rows['2025/1']['stints']['1'] = {
      'production_key' => 'source-3|https://second.example/sports/mens-basketball/roster/alpha/101',
      'team_id' => second.id.to_s, 'identity_evidence_source_ids' => %w[source-1 source-3], 'player_points' => '999999'
    }
    allow(Departures::DecisionForm).to receive(:table_choices).and_call_original
    report = save_departure_rows(batch, rows).report
    expect(Departures::DecisionForm).to have_received(:table_choices).exactly(2).times
    expect(report.fetch('errors')).to eq([])
    expect(report.fetch('selections').first['stints'].map { |stint| [stint['team_id'], stint['player_points']] }).to eq(
      [[team.id, 500], [second.id, 500]]
    )
    expect(batch.decisions.first['stints'].size).to eq(2)
  end
end
