# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe OffseasonInputs::DepartureBundle do
  let(:directory) { Dir.mktmpdir('departures-preview') }
  let(:team) { create(:team, school: 'Sample School') }
  let(:other_team) { create(:team, school: 'Other School') }
  let(:sources) do
    [snapshot('draft', 'nba_results', 'https://www.nba.com/news/2025-nba-draft-order', 'draft.html'),
     snapshot('school', 'sidearm_totals', 'https://school.example/sports/mens-basketball/stats/2024-25', 'school.html')
       .merge('team_name_source' => 'Sample School', 'scope' => Departures::Contract::SCOPE, 'scope_evidence' => 'Verified final scope')]
  end
  let(:manifest) do
    { 'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => (1..60).to_a, 'sources' => sources }
  end
  let(:dataset) { Departures::AnnualDataset.new(manifest:, directory:).call }
  let(:decisions) do
    [eligible('2025/1', 'alpha/101')] + (2..59).map do |pick|
      { 'selection_key' => "2025/#{pick}", 'status' => 'verified_no_college', 'reason' => 'Synthetic reviewed no-college evidence',
        'evidence_source_ids' => ['draft'] }
    end + [eligible('2025/60', 'beta/102')]
  end
  let(:review) do
    { 'dataset_revision' => dataset.fetch('dataset_revision'), 'revision_id' => 'review-1', 'reviewed_by' => 'Test reviewer',
      'reviewed_at' => '2026-10-13T12:00:00Z', 'decision' => 'approved', 'decisions' => decisions }
  end
  let(:season) { create(:season, year: 2026) }
  let(:paths) do
    { capture_dir: directory, dataset_path: File.join(directory, 'dataset.json'), review_path: File.join(directory, 'review.json') }
  end
  let(:bundle) { described_class.new(paths, season).call }

  before do
    create(:team_season, team:, season:)
    create(:team_season, team: other_team, season:)
    save_files
  end

  def save_files
    Departures::Contract.write_bytes(File.join(directory, 'manifest.json'), JSON.generate(manifest))
    Departures::Contract.write_bytes(paths.fetch(:dataset_path), JSON.generate(dataset))
    File.write(paths.fetch(:review_path), JSON.generate(review))
  end

  def import_bundle
    publication = { version: 'departure-review-1', reason: 'Verified evidence review', predecessor_id: nil,
                    input_hash: Departures::Contract.digest(bundle) }
    importer = OffseasonInputs::Import.new(season:, kind: 'departures', paths:, publication:)
    importer.call(preview_key: importer.preview.fetch('preview_key'))
  end

  after { FileUtils.remove_entry(directory) }

  def snapshot(id, type, url, fixture)
    bytes = Rails.root.join('spec/fixtures/departures', fixture).binread
    sha = Digest::SHA256.hexdigest(bytes)
    File.binwrite(File.join(directory, "#{sha}.html"), bytes)
    { 'id' => id, 'type' => type, 'url' => url, 'snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.html",
      'snapshot_kind' => 'raw_html', 'http_status' => 200, 'captured_at' => '2026-10-13T11:00:00Z',
      'observed_at' => '2026-10-13T11:00:00Z', 'source_as_of' => nil, 'source_as_of_reason' => 'Unavailable' }
  end

  def eligible(key, player)
    { 'selection_key' => key, 'status' => 'eligible_prior_season', 'reason' => 'Reviewed draft profile and prior-season roster identity',
      'evidence_source_ids' => %w[draft school],
      'stints' => [{ 'source_id' => 'school', 'player_source_url' => "https://school.example/sports/mens-basketball/roster/#{player}",
                     'team_id' => team.id, 'identity_evidence_source_ids' => %w[draft school] }] }
  end

  it 'persists all selections, multiple departures, audit units and complete verified zero' do
    import_bundle
    revision = OffseasonInputRevision.last
    expect(revision.payload.dig('report', 'selections').size).to eq(60)
    expect(revision.team_input(team.id)).to include('known_points_subtotal' => 500, 'team_points' => 2000, 'loss_share' => 0.25)
    expect(revision.team_input(other_team.id)).to include('loss_share' => 0.0, 'reason' => 'verified_zero')
    expect(revision.payload.dig('report', 'selections').last.fetch('stints').first).to include('player_points' => 0, 'games' => 2)
    expect(Base64.strict_decode64(revision.payload.dig('evidence', 'draft', 'snapshot_base64'))).to eq(
      Rails.root.join('spec/fixtures/departures/draft.html').binread
    )
  end

  it 'retains approved partial accounting with unknown losses and explicit exclusions' do
    decisions.pop
    File.write(paths.fetch(:review_path), JSON.generate(review))
    import_bundle
    revision = OffseasonInputRevision.last
    expect(revision.payload.dig('report', 'coverage_complete')).to be false
    expect(revision.team_input(team.id)).to include('known_points_subtotal' => 500, 'loss_share' => nil)
    expect(revision.team_input(other_team.id).fetch('loss_share')).to be_nil
    expect(revision.payload.dig('report', 'selections').last.fetch('status')).to eq('unknown_participation')
  end

  it 'retains not-applicable evidence without interpreting affiliation as production' do
    decisions.last.replace('selection_key' => '2025/60', 'status' => 'verified_nonparticipant',
                           'reason' => 'Verified no participation', 'evidence_source_ids' => ['draft'])
    File.write(paths.fetch(:review_path), JSON.generate(review))
    expect(bundle.dig('report', 'selections').last).to include('status' => 'verified_nonparticipant', 'stints' => [])
  end

  it 'rejects pending and rejected file approval' do
    %w[pending rejected].each do |status|
      review['decision'] = status
      File.write(paths.fetch(:review_path), JSON.generate(review))
      expect { bundle }.to raise_error(ArgumentError, /approval/)
    end
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'rejects saved hash tampering, snapshot corruption and wrong target season' do
    saved = dataset.merge('dataset_revision' => 'wrong')
    File.write(paths.fetch(:dataset_path), JSON.generate(saved))
    expect { bundle }.to raise_error(ArgumentError, /source replay/)
    File.write(paths.fetch(:dataset_path), JSON.generate(dataset))
    File.write(File.join(directory, sources.first.fetch('snapshot_location')), 'corrupt')
    expect { bundle }.to raise_error(ArgumentError, /source replay/)
    expect { described_class.new(paths, create(:season, year: 2027)).call }.to raise_error(ArgumentError)
  end

  it 'refuses publication of explicit conflicts even in a reviewed partial file' do
    decisions.last.replace('selection_key' => '2025/60', 'status' => 'conflicting_evidence',
                           'reason' => 'Unresolved contradictory participation', 'evidence_source_ids' => ['draft'])
    File.write(paths.fetch(:review_path), JSON.generate(review))
    expect { import_bundle }.to raise_error(ArgumentError, /conflicting departure evidence/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'rejects duplicate decisions and conflicting team denominators without publication' do
    decisions << decisions.first
    File.write(paths.fetch(:review_path), JSON.generate(review))
    expect { import_bundle }.to raise_error(ArgumentError, /Duplicate review/)
    expect(OffseasonInputRevision.count).to eq(0)
  end
end
