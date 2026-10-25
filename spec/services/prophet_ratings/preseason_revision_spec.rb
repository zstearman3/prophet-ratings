# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRevision do
  let(:version) { RatingsConfigVersion.publish! }
  let(:revision_version) { create(:ratings_config_version) }
  let(:season) { create(:season, average_pace: nil, average_efficiency: nil) }
  let!(:home) { create(:team_season, season:) }
  let!(:away) { create(:team_season, season:) }
  let(:revision) { described_class.new(season, ratings_config_version: revision_version) }

  before { ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call }

  def publish_revision
    revision.call(preview_key: revision.preview.fetch(:preview_key))
  end

  def legacy_report_row(row, inputs, config)
    prior = row.preseason_prior
    {
      team_id: row.team_id, team_season_id: row.id, added: prior.blank?,
      profile_before: prior&.inputs&.fetch('profile', nil), profile_after: inputs['profile'],
      outputs_before: prior&.outputs, outputs_after: ProphetRatings::PreseasonPriorFormula.new(inputs, config).call,
      coaching: ProphetRatings::PreseasonPriorFormula.new(inputs, config).pace_report,
      efficiency: ProphetRatings::PreseasonPriorFormula.new(inputs, config).efficiency_report, inputs: inputs
    }
  end

  def scheduled_forecast
    game = create(:game, season:, status: :scheduled, start_time: season.start_date.in_time_zone + 12.hours)
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
    ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: version).call
  end

  it 'preserves ordered preview rows and preview identity across reload-shaped JSON' do
    report = revision.preview
    calculator = ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: revision_version)
    expected = season.rating_team_seasons.order(:team_id).map do |row|
      legacy_report_row(row, calculator.preview_inputs(row).as_json, revision_version.config)
    end

    expect(report[:teams]).to eq(expected)
    expect(report[:teams].pluck(:team_id)).to eq([home.team_id, away.team_id].sort)
    expected_priors = [home, away].sort_by(&:team_id).map { |row| row.reload.preseason_prior.outputs }
    expect(report[:teams].pluck(:outputs_before)).to eq(expected_priors)
    legacy_report = report.except(:teams, :preview_key).merge(teams: expected)
    legacy_key = Digest::SHA256.hexdigest(described_class.canonical_json(legacy_report.as_json).to_json)
    expect(report[:preview_key]).to eq(legacy_key)

    reloaded_revision = described_class.new(
      Season.find(season.id), ratings_config_version: RatingsConfigVersion.find(revision_version.id)
    )
    expect(reloaded_revision.preview[:preview_key]).to eq(report[:preview_key])
  end

  it 'previews corrected coverage without writes, then publishes while preserving frozen outputs' do
    prediction = scheduled_forecast
    original = [version.reload.attributes, prediction.attributes, TeamRatingSnapshot.order(:id).map(&:attributes),
                PreseasonPrior.order(:id).map(&:attributes)]
    create(:team_offseason_profile, team_season: home, manual_adjustment: 2)
    added = create(:team_season, season:)
    report = revision.preview
    aggregate_failures 'preview without writes' do
      expect(report[:teams].find { |row| row[:team_id] == added.team_id }[:added]).to be(true)
      corrected = report[:teams].find { |row| row[:team_id] == home.team_id }
      expect(corrected[:profile_after]['attributes']['source_reference']).to eq('Synthetic operator evidence')
      expect(corrected[:outputs_after]['preseason_adj_offensive_efficiency']).to eq(107.5)
      expect(report[:baselines][:after]['average_efficiency']).to eq(106.167)
      expect([PreseasonPrior.count, season.reload.preseason_revision]).to eq([2, nil])
    end

    revision.call(preview_key: report[:preview_key])
    aggregate_failures 'published revision preserves historical outputs' do
      expect([version.reload.attributes, prediction.reload.attributes,
              TeamRatingSnapshot.where(ratings_config_version: version).order(:id).map(&:attributes),
              PreseasonPrior.where(ratings_config_version: version).order(:id).map(&:attributes)]).to eq(original)
      expect(season.reload.preseason_revision).to eq(revision_version)
      expect(home.reload.overall_rank).to eq(1)
      expect(added.reload.preseason_prior.ratings_config_version).to eq(revision_version)
      expect(prediction.replay).to eq(ProphetRatings::ForecastContext.new(original[1].fetch('calculation_context')).predictor.call)
    end
  end

  it 'reuses identities on an unchanged rerun and rejects later corrections under the published version' do
    profile = create(:team_offseason_profile, team_season: home, manual_adjustment: 0)
    publish_revision
    identities = [PreseasonPrior.order(:id).ids, TeamRatingSnapshot.order(:id).ids]
    publish_revision
    expect([PreseasonPrior.order(:id).ids, TeamRatingSnapshot.order(:id).ids]).to eq(identities)
    profile.update!(manual_adjustment: 1)
    expect { revision.preview }.to raise_error(ArgumentError, /new MODEL_VERSION/)
  end

  it 'requires a new version and an unchanged reviewed preview' do
    expect { described_class.new(season, ratings_config_version: version).preview }.to raise_error(ArgumentError, /new immutable/)
    report = revision.preview
    create(:team_offseason_profile, team_season: home, manual_adjustment: 1)
    expect { revision.call(preview_key: report[:preview_key]) }.to raise_error(ArgumentError, /rerun.*preview/)
    expect(PreseasonPrior.count).to eq(2)
  end

  it 'refuses legacy baseline changes and profiles with missing evidence' do
    create(:prediction, game: create(:game, season:, status: :scheduled), ratings_config_version: version,
                        home_team_snapshot: home.team_rating_snapshots.first, away_team_snapshot: away.team_rating_snapshots.first)
    profile = create(:team_offseason_profile, team_season: home, manual_adjustment: 1)
    expect { revision.preview }.to raise_error(ArgumentError, /Legacy forecasts/)
    # Synthetic historical row lacking provenance; ordinary edits must validate it.
    profile.update_columns(source_reference: nil) # rubocop:disable Rails/SkipsModelValidations
    expect { revision.preview }.to raise_error(ArgumentError, /Resolve offseason profile.*source/i)
  end

  it 'rolls back priors, ranks, snapshots and selection after a mid-publication failure' do
    report = revision.preview
    original = [season.reload.attributes, home.reload.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]
    service = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise('publication failed')
    Season.transaction do
      expect { revision.call(preview_key: report[:preview_key]) }.to raise_error('publication failed')
    end
    expect([season.reload.attributes, home.reload.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]).to eq(original)
    expect(PreseasonPrior.count).to eq(2)
  end

  it 'rejects active, final and in-season outputs with recovery instructions' do
    season.update!(current: true)
    expect { revision.preview }.to raise_error(ArgumentError, /scoped season:rebuild_ratings/)
    season.update!(current: false)
    game = create(:game, season:, status: :final)
    expect { revision.preview }.to raise_error(ArgumentError, /scoped season:rebuild_ratings/)
    game.destroy!
    ProphetRatings::TeamRatingSnapshotService.new(season:, as_of: season.start_date, ratings_config_version: version).call
    expect { revision.preview }.to raise_error(ArgumentError, /scoped season:rebuild_ratings/)
  end

  it 'requires complete selected revision coverage at activation' do
    publish_revision
    added = create(:team_season, season:)
    expect { season.set_current! }.to raise_error(ArgumentError, /Selected preseason revision.*#{added.team_id}/)
  end

  it 'publishes edited profile evidence under a new version and replays it without mutable sources' do
    target = create(:season, year: season.year + 1)
    row = create(:team_season, season: target, team: home.team)
    profile = create(:team_offseason_profile, team_season: row, manual_adjustment: 1, returning_minutes_pct: nil)
    ProphetRatings::PreseasonInitializer.new(target, ratings_config_version: version).call
    old = row.reload.preseason_prior
    profile.update!(manual_adjustment: 2, returning_minutes_pct: 0, source_reference: 'Corrected synthetic observation')
    operation = described_class.new(target, ratings_config_version: revision_version)
    report = operation.preview
    operation.call(preview_key: report[:preview_key])
    captured = row.reload.preseason_prior
    expect(old.reload.inputs.dig('profile_values', 'returning_minutes_pct')).to be_nil
    expect(captured.inputs.dig('profile_values', 'returning_minutes_pct')).to eq(0)
    expect(captured.inputs.dig('profile', 'attributes').slice('source_reference', 'observed_on', 'input_units'))
      .to eq(profile.attributes.slice('source_reference', 'observed_on', 'input_units').as_json)
    profile.update!(manual_adjustment: 4)
    expect(ProphetRatings::PreseasonPriorFormula.new(captured.inputs, revision_version.config).call).to eq(captured.outputs)
  end

  it 'publishes only reviewed included teams while preserving previous excluded snapshots and forecasts' do
    prediction = scheduled_forecast
    old_snapshot = away.team_rating_snapshots.first
    original = [prediction.attributes, old_snapshot.attributes]
    create(:team_alias, team: home.team, value: home.team.school)
    SeasonParticipationReview.new(season).apply(
      'evidence' => 'Synthetic review', 'reviewed_by' => 'Test operator',
      'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601, 'evidence' => 'Test dates' },
      'teams' => [{ 'team_id' => home.team_id, 'status' => 'included', 'reason' => 'Verified' },
                  { 'team_id' => away.team_id, 'status' => 'excluded', 'reason' => 'Verified departure' }],
      'unresolved_identities' => []
    )
    publish_revision
    expect(season.team_rating_snapshots.where(ratings_config_version: revision_version).pluck(:team_id)).to eq([home.team_id])
    expect([prediction.reload.attributes, old_snapshot.reload.attributes]).to eq(original)
    expect(away.reload.overall_rank).to be_nil
    expect { season.set_current! }.not_to raise_error
  end

  it 'binds the preview to season dates and rejects incompatible stored versions' do
    report = revision.preview
    season.update!(start_date: season.start_date + 1.day)
    expect { revision.call(preview_key: report[:preview_key]) }.to raise_error(ArgumentError, /in-season outputs|rerun.*preview/)
    incomplete = create(:ratings_config_version, name: 'legacy')
    incomplete.update_columns(config: { bundle_name: 'legacy' }) # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.new(season, ratings_config_version: incomplete) }.to raise_error(ArgumentError, /legacy|contract/i)
  end

  it 'requires a new publication after a participant is removed from the selected revision roster' do
    create(:team_alias, team: home.team, value: home.team.school)
    create(:team_alias, team: away.team, value: away.team.school)
    review = SeasonParticipationReview.new(season)
    document = {
      'evidence' => 'Synthetic review', 'reviewed_by' => 'Test operator',
      'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601, 'evidence' => 'Test dates' },
      'teams' => [{ 'team_id' => home.team_id, 'status' => 'included', 'reason' => 'Verified' },
                  { 'team_id' => away.team_id, 'status' => 'included', 'reason' => 'Verified' }],
      'unresolved_identities' => []
    }
    review.apply(document)
    publish_revision
    original = [season.reload.average_efficiency, home.reload.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]
    document['teams'].last.merge!('status' => 'excluded', 'reason' => 'Verified departure')
    review.apply(document)
    expect { season.set_current! }.to raise_error(ArgumentError, /deliberate new-version publication/)
    expect([season.reload.average_efficiency, home.reload.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]).to eq(original)
    expect(season.reload).not_to be_current
  end
end
