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

  it 'captures imported evidence for pure scoring and replay without mutable revision lookups' do
    import_bundle
    revision = OffseasonInputRevision.last
    captured = ProphetRatings::DepartureContributionEvidence.capture(revision)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:preseason][:departures] = YAML.load_file(Rails.root.join('config/examples/departures_r3.yml')).symbolize_keys
    inputs = { team_id: team.id, target_year: season.year, profile_values: {},
               previous_values: { adj_offensive_efficiency: 100, adj_defensive_efficiency: 100 }, reviewed_departures: captured }
    report = ProphetRatings::DepartureContribution.new(inputs, config).call
    expect(report).to include(loss_share: 0.25, contribution: -0.5)
    expect(report[:inputs].dig('reviewed_departures', 'revision')).to include('input_hash' => revision.input_hash)
    TeamOffseasonProfile.find_each { |profile| profile.update!(departure_revision: nil) }
    expect(ProphetRatings::DepartureContribution.new(report[:inputs], report[:configuration]).call).to eq(report)
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

  context 'when publishing database recruiting and reviewed departure evidence' do
    include ActiveSupport::Testing::TimeHelpers

    let(:version) do
      config = RatingsConfigVersion.authored_config.deep_dup
      config[:bundle_name] = 'saved-file-workflow'
      config[:preseason].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')).deep_symbolize_keys)
      RatingsConfigVersion.publish!(config)
    end
    let(:operation) { ProphetRatings::PreseasonRevision.new(season, ratings_config_version: version) }
    let(:home) { season.team_seasons.find_by!(team:) }
    let(:away) { season.team_seasons.find_by!(team: other_team) }

    before do
      travel_to((season.start_date - 1.day).in_time_zone + 12.hours)
      previous = create(:season, year: 2025, average_efficiency: 100, average_pace: 70)
      [team, other_team].each do |participant|
        create(:team_season, season: previous, team: participant,
                             adj_offensive_efficiency: 100, adj_defensive_efficiency: 100, adj_pace: 70)
      end
      import_recruiting
      import_bundle
    end

    def import_recruiting
      batch = RecruitingBatch.find_by(season:) || capture_recruiting
      review = Recruiting::BatchReview.new(batch)
      review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'Test reviewer')
    end

    def capture_recruiting
      extract = JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read)
      extract.merge!('source_year' => 2025, 'target_season' => 2026,
                     'source_url' => 'https://247sports.com/Season/2025-Basketball/CompositeTeamRankings/')
      extract['rows'].first.merge!('team_label' => team.school, 'class_points' => '70')
      bytes = JSON.generate(extract)
      dataset = Recruiting::Dataset.new(bytes, 'Synthetic recruiting extract')
      RecruitingBatch.create!(season:, source_year: 2025, status: 'ready', source_status: 'ok',
                              extract_bytes: bytes, snapshot_bytes: 'Synthetic recruiting extract',
                              dataset_revision: dataset.manifest.fetch('dataset_revision')).tap do |batch|
        Recruiting::Preview.new(dataset, season).call.fetch('rows').each do |row|
          batch.entries.create!(RecruitingEntry.source_attributes(row))
        end
      end
    end

    def publish_reviewed
      operation.call(preview_key: operation.preview.fetch(:preview_key))
    end

    def scheduled_prediction
      game = create(:game, season:, status: :scheduled, start_time: season.start_date.in_time_zone + 12.hours)
      create(:team_game, game:, team_season: home, team:, home: true)
      create(:team_game, game:, team_season: away, team: other_team, home: false)
      ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: version).call
    end

    it 'previews the hand-calculated combined adjustment from both reviewed evidence imports without publishing' do
      report = operation.preview
      row = report[:teams].find { |entry| entry[:team_id] == team.id }
      # P=70, N0=0: R=5; two eligible players total 500/2000: D=-.5; A=4.5.
      expect(row[:efficiency]).to include(pre_cap_sum: 4.5, adjustment: 4.5, offense_allocation: 2.25, defense_allocation: -2.25)
      expect(row[:efficiency][:departures]).to include(loss_share: 0.25)
      expect(PreseasonPrior.count).to eq(0)
    end

    it 'publishes the combined net adjustment exactly once into core values, ranks and snapshot provenance' do
      publish_reviewed
      expect(home.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency',
                                              'adj_pace')).to eq([102.25, 97.75, 70])
      expect([home.overall_rank, away.reload.overall_rank]).to eq([1, 2])
      snapshot = home.team_rating_snapshots.find_by!(ratings_config_version: version)
      expect([snapshot.adj_offensive_efficiency, snapshot.adj_defensive_efficiency, snapshot.overall_rank]).to eq([102.25, 97.75, 1])
      prior = home.preseason_prior
      expect(snapshot.stats.dig('preseason_prior', 'inputs')).to eq(prior.inputs)
    end

    it 'preserves all-selection evidence, captures, snapshots and frozen forecasts on unchanged input and initializer reruns' do
      publish_reviewed
      expect(home.reload.preseason_prior.inputs.dig('reviewed_departures', 'selections').size).to eq(60)
      prediction = scheduled_prediction
      expect(prediction.calculation_context.dig('snapshots', 0, 'ratings', 'adj_offensive_efficiency')).to eq(102.25)
      before = [OffseasonInputRevision.order(:id).map(&:attributes), PreseasonPrior.order(:id).map(&:attributes),
                TeamRatingSnapshot.order(:id).map(&:attributes), prediction.attributes]
      import_bundle
      import_recruiting
      ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
      expect([OffseasonInputRevision.order(:id).map(&:attributes), PreseasonPrior.order(:id).map(&:attributes),
              TeamRatingSnapshot.order(:id).map(&:attributes), prediction.reload.attributes]).to eq(before)
      expect(season.reload).not_to be_current
    end

    it 'tunes only configuration against unchanged imported evidence and preserves the prior forecast and replay' do
      publish_reviewed
      prior = home.reload.preseason_prior
      prediction = scheduled_prediction
      frozen_prediction = prediction.attributes
      frozen_prior = prior.attributes
      config = version.config.deep_dup
      config['bundle_name'] = 'saved-file-tuned'
      config['preseason']['recruiting']['class_points_upper'] = 80
      tuned = RatingsConfigVersion.publish!(config)
      revision = ProphetRatings::PreseasonRevision.new(season, ratings_config_version: tuned)
      preview = revision.preview
      # The same P=70 now gives q=.5, so A=2.5-.5=2, allocated +/-1.
      expect(preview[:teams].first[:efficiency]).to include(pre_cap_sum: 2, adjustment: 2)
      expect { revision.call(preview_key: preview.fetch(:preview_key)) }.not_to change(OffseasonInputRevision, :count)
      expect(home.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency')).to eq([101, 99])
      expect([prior.reload.attributes, prediction.reload.attributes]).to eq([frozen_prior, frozen_prediction])
      expect(ProphetRatings::PreseasonPriorFormula.new(prior.inputs, prior.inputs.fetch('configuration')).call).to eq(prior.outputs)
    end

    it 'keeps imported evidence but rolls back all rating publication writes on failure' do
      original = season.team_seasons.order(:id).map(&:attributes)
      evidence = OffseasonInputRevision.order(:id).map(&:attributes)
      snapshots = instance_double(ProphetRatings::TeamRatingSnapshotService)
      allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(snapshots)
      allow(snapshots).to receive(:call).and_raise('Synthetic publication failure')
      expect { publish_reviewed }.to raise_error('Synthetic publication failure')
      expect([PreseasonPrior.count, TeamRatingSnapshot.count, season.reload.preseason_revision_id]).to eq([0, 0, nil])
      expect(season.team_seasons.order(:id).map(&:attributes)).to eq(original)
      expect(OffseasonInputRevision.order(:id).map(&:attributes)).to eq(evidence)
    end
  end
end
