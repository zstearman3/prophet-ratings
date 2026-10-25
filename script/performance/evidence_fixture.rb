# frozen_string_literal: true

module OffseasonPerformance
  # Replays real departure parsing/review and retains recruiting evidence through normal revision validation.
  class EvidenceFixture
    def initialize(state)
      @state = state
    end

    def departures
      Dir.mktmpdir { |directory| acquire_departure(directory) }
    end

    def acquire_departure(directory)
      plan, evidence = retained_sources(directory)
      @state.batch = DepartureBatch.create!(season: @state.season, plan:)
      dataset = Departures::AnnualDataset.new(manifest: plan, directory:).call
      EvidenceFixture.verify_dataset(dataset)
      persist_acquisition(plan, dataset, evidence)
    end

    def self.verify_dataset(dataset)
      failures = dataset.fetch('failures')
      raise failures.inspect if failures.any?
    end

    def persist_acquisition(plan, dataset, evidence)
      @state.attempt = @state.batch.acquisitions.create!(plan:, manifest: plan, dataset:, evidence:, status: 'completed')
      approve_departure(dataset, evidence)
    end

    def approve_departure(dataset, evidence)
      rows = Departures::DecisionForm.new(dataset).call(decisions)
      review = EvidenceFixture.departure_review(dataset, rows, @state.admin.email)
      payload = EvidenceFixture.departure_payload(dataset, evidence, review)
      persist_departure(rows, payload)
    end

    def self.departure_review(dataset, rows, actor)
      { 'dataset_revision' => dataset.fetch('dataset_revision'), 'decisions' => rows,
        'revision_id' => 'synthetic-departures-v1', 'decision' => 'approved',
        'reviewed_by' => actor, 'reviewed_at' => Content::TIME, 'partial_acknowledgement' => {} }
    end

    def self.departure_payload(dataset, evidence, review)
      report = Departures::Preview.new(dataset:, review:).call
      inputs = report.fetch('teams').to_h do |entry|
        [entry.fetch('team_id').to_s, entry.merge('units' => Departures::ProductionStint::UNITS,
                                                  'loss_share_unit' => 'fraction_of_team_points')]
      end
      { 'kind' => 'departures', 'dataset_hash' => dataset.fetch('dataset_revision'),
        'review_hash' => Departures::Contract.digest(review), 'dataset' => dataset, 'review' => review,
        'report' => report, 'evidence' => evidence, 'team_inputs' => inputs }
    end

    def persist_departure(rows, payload)
      @state.departure = EvidenceFixture.revision(@state.season, 'departures', payload)
      publish_batch(rows)
      populate_profiles
    end

    def publish_batch(rows)
      actor = @state.admin.email
      @state.batch.update!(decisions: rows, status: 'published', revision: @state.departure, reviewed_by: actor, reviewed_at: Content::TIME)
    end

    def populate_profiles
      @state.season.team_seasons.each do |row|
        TeamOffseasonProfile.create!(team_season: row, departure_revision: @state.departure)
      end
    end

    def self.revision(season, kind, payload)
      OffseasonInputRevision.create!(season:, kind:, version: "synthetic-#{kind}-v1", reason: 'Approved by admin',
                                     payload:, input_hash: Departures::Contract.digest(payload),
                                     dataset_hash: payload['dataset_hash'], review_hash: payload['review_hash'])
    end

    def retained_sources(directory)
      storage = { directory:, evidence: {} }
      sources = @state.content.each_source.map { |source, html| EvidenceFixture.retain_source(source, html, storage) }
      [Content.plan.merge('sources' => sources), storage.fetch(:evidence)]
    end

    def self.retain_source(source, html, storage)
      sha = Digest::SHA256.hexdigest(html)
      File.write(File.join(storage.fetch(:directory), "#{sha}.html"), html)
      storage.fetch(:evidence)[source.fetch('id')] = { 'snapshot_base64' => Base64.strict_encode64(html) }
      source.merge('snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.html")
    end

    def decisions
      (1..60).to_h { |pick| decision(pick) }
    end

    def decision(pick)
      team = pick - 1
      stints = [stint(team, EvidenceFixture.first_athlete(team))]
      stints << stint(1, 1) if pick == 1
      ["2025/#{pick}", EvidenceFixture.reviewed_decision(team, stints)]
    end

    def self.first_athlete(team)
      second = team == 1
      second ? 17 : (team * Content::PLAYERS) + 1
    end

    def self.reviewed_decision(team, stints)
      { 'status' => 'eligible_prior_season', 'reason' => 'Reviewed synthetic identity and school stints',
        'evidence_source_ids' => ['draft', "school-#{team}-0"],
        'stints' => stints.each_with_index.to_h { |value, index| [index.to_s, value] } }
    end

    def stint(team, athlete)
      { 'production_key' => "school-#{team}-0|https://synthetic-#{team}.example/sports/mens-basketball/roster/athlete-#{athlete}",
        'team_id' => @state.teams.fetch(team).id.to_s, 'identity_evidence_source_ids' => ['draft', "school-#{team}-0"] }
    end

    def recruiting
      review = EvidenceFixture.recruiting_review(@state.admin.email)
      inputs = recruiting_inputs
      payload = EvidenceFixture.recruiting_payload(inputs, review)
      revision = EvidenceFixture.revision(@state.season, 'recruiting', payload)
      recruiting_profiles(revision)
    end

    def recruiting_inputs
      @state.teams.to_h { |team| EvidenceFixture.recruiting_input(team) }
    end

    def self.recruiting_review(actor)
      { 'review_status' => 'reviewed', 'approval' => { 'approved_by' => actor, 'approved_at' => Content::TIME } }
    end

    def self.recruiting_input(team)
      id = team.id
      [id.to_s, { 'status' => 'verified_points', 'class_points' => '25.0',
                  'units' => { 'class_points' => '247_recruit_composite_class_points' },
                  'row' => { 'school' => team.school, 'rank' => id, 'commit_count' => 3 }, 'reason' => 'reviewed_source_row' }]
    end

    def self.recruiting_payload(inputs, review)
      { 'kind' => 'recruiting', 'dataset' => inputs, 'dataset_hash' => Departures::Contract.digest(inputs),
        'review' => review, 'review_hash' => Departures::Contract.digest(review), 'team_inputs' => inputs,
        'evidence' => { 'source' => 'synthetic offline recruiting transcription', 'captured_at' => Content::TIME } }
    end

    def recruiting_profiles(revision)
      @state.season.team_seasons.each { |row| EvidenceFixture.recruiting_profile(row, revision) }
    end

    def self.recruiting_profile(row, revision)
      profile = row.team_offseason_profile || row.build_team_offseason_profile
      profile.update!(recruiting_revision: revision, recruiting_score: 25, returning_minutes_pct: 0.75,
                      observed_on: '2025-06-30', source_reference: 'Synthetic retained reviewed evidence',
                      input_units: TeamOffseasonProfile::INPUT_UNITS)
    end
  end
end
