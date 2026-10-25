# frozen_string_literal: true

module OffseasonPerformance
  # Builds fixed team membership/history and real formula-valid retained target prior captures.
  class HistoryFixture
    def initialize(state)
      @state = state
    end

    def create_teams
      @state.teams = Array.new(Content::TEAMS) { |index| create_team(index) }
      create_coaching
    end

    def create_team(index)
      team = Team.create!(school: @state.content.school(index), slug: "synthetic-#{index}", url: "synthetic-#{index}")
      create_memberships(team, index)
      team
    end

    def create_memberships(team, index)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: ((index + 1) * 10).to_s)
      TeamSeason.create!(team:, season: @state.season)
      rating = index % 10
      TeamSeason.create!(team:, season: @state.prior, ratings_config_version: @state.model,
                         adj_offensive_efficiency: 100 + rating, adj_defensive_efficiency: 100, adj_pace: 68, rating:)
    end

    def create_coaching
      CoachingReview.create!(year: 2026, ready: true, discovery_status: 'complete', discovered_at: Content::TIME)
      @state.teams.first(20).each_with_index { |team, index| create_coach(team, index) }
      CoachingReview.find_by!(year: 2026).update!(ready: true)
    end

    def create_coach(team, index)
      CoachingChange.create!(team:, effective_year: 2026, coach_name: "Synthetic Coach #{index}", status: 'confirmed',
                             previous_team: @state.teams[index + 20], previous_year: 2025, previous_role: 'head_coach',
                             full_season_head_coach: true, previous_season_d1: true)
    end

    def history
      rows = @state.prior.team_seasons.order(:team_id).to_a
      (165 * @state.content.scale).times { |day| HistoryFixture.insert_snapshots(history_rows(rows, day)) }
      legacy_priors
    end

    def history_rows(rows, day)
      context = { season_id: @state.prior.id, ratings_config_version_id: @state.model.id, snapshot_date: Date.new(2024, 5, 1) + day }
      rows.map { |row| HistoryFixture.snapshot(row).merge(context) }
    end

    def self.snapshot(row)
      team_id = row.team_id
      { team_id:, team_season_id: row.id, adj_offensive_efficiency: 100, adj_defensive_efficiency: 100,
        adj_pace: 68, rating: 0, stats: { 'overall_rank' => team_id, 'adj_turnover_rate' => 0.18 } }
    end

    def self.insert_snapshots(values)
      # Synthetic bulk history deliberately uses the schema's FK/unique constraints, outside model calculation callbacks.
      connection = TeamRatingSnapshot.connection
      document = connection.quote(JSON.generate(values))
      connection.execute(<<~SQL.squish)
        INSERT INTO team_rating_snapshots
          (team_id, team_season_id, season_id, ratings_config_version_id, snapshot_date,
           adj_offensive_efficiency, adj_defensive_efficiency, adj_pace, rating, stats, created_at, updated_at)
        SELECT team_id, team_season_id, season_id, ratings_config_version_id, snapshot_date,
               adj_offensive_efficiency, adj_defensive_efficiency, adj_pace, rating, stats,
               '2025-06-30T12:00:00Z', '2025-06-30T12:00:00Z'
        FROM jsonb_to_recordset(#{document}::jsonb) AS x(
          team_id bigint, team_season_id bigint, season_id bigint, ratings_config_version_id bigint,
          snapshot_date date, adj_offensive_efficiency numeric, adj_defensive_efficiency numeric,
          adj_pace numeric, rating numeric, stats jsonb)
      SQL
    end

    def legacy_priors
      season = @state.season
      model = @state.model
      calculator = ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: model)
      season.team_seasons.order(:team_id).each { |row| legacy_prior(row, calculator, model) }
    end

    def legacy_prior(row, calculator, model)
      inputs = legacy_inputs(row, calculator)
      PreseasonPrior.create!(team_season: row, ratings_config_version: model, inputs:,
                             outputs: ProphetRatings::PreseasonPriorFormula.new(inputs, model.config).call)
    end

    def legacy_inputs(row, calculator)
      observations = HistoryFixture.source_observations(@state.attempt, row.team.school)
      calculator.preview_inputs(row).as_json.merge('legacy_source_observations' => observations)
    end

    def self.source_observations(attempt, school)
      production = matching_sources(attempt.dataset.fetch('production'), school)
      sources = matching_sources(attempt.manifest.fetch('sources'), school)
      evidence = attempt.evidence.slice(*sources.pluck('id'))
      { 'production' => production, 'sources' => sources, 'evidence' => evidence }
    end

    def self.matching_sources(rows, school)
      rows.select { |row| row['team_name_source'] == school }
    end
  end
end
