# frozen_string_literal: true

module OffseasonPerformance
  # Retains full real-normalizer finals and ten representative local statistical shadows.
  class CbbdFixture
    def initialize(state)
      @state = state
    end

    def call(prior)
      observations = observations(prior)
      run = CbbdFixture.persist_replay(prior, observations)
      CbbdFixture.finalize_run(run, prior, observations.first(10))
      @state.cbbd = CbbdReviewRun.select(:id, :season_id).find(run.id)
    end

    def observations(prior)
      fixture = JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read)
      SetupPhase.call('cbbd_normalization') do
        Array.new(10_000 * @state.content.scale) { |index| observation(fixture, prior, index) }
      end
    end

    def self.persist_replay(prior, observations)
      replay = { 'bounds' => { 'season' => prior.year, 'start_date' => '2024-11-01', 'end_date' => '2025-04-10' },
                 'observations' => observations, 'complete' => true, 'acquisition' => { 'complete' => true, 'decisions' => [] } }
      SetupPhase.call('cbbd_persistence') do
        CbbdReviewRun.create!(season: prior, start_date: '2024-11-01', end_date: '2025-04-10', maximum_requests: 20,
                              retries: 0, status: 'completed', normalized_replay: replay,
                              manifest: { 'finalized' => true, 'acquisition' => { 'captures' => [] } })
      end
    end

    def self.finalize_run(run, prior, observations)
      digest = SetupPhase.call('cbbd_evidence_digest') { run.evidence_hash }
      run.update!(evidence_digest: digest)
      CbbdFixture.local_games(prior, observations)
    end

    def verify_comparison
      id = CbbdReviewRun.where(id: @state.cbbd.id).pick(:active_comparison_id)
      comparison = CbbdReviewComparison.find(id)
      comparison.verify_artifact
      raise 'Missing representative CBBD shadow comparisons' unless comparison.report.dig('shadow', 'games_compared') == 10
    end

    def self.local_games(prior, observations)
      observations.each do |row|
        game = local_game(prior, row)
        local_sides(prior, row, game)
      end
    end

    def self.local_game(prior, row)
      id = row.fetch('source_game_id')
      game = Game.create!(season: prior, url: "https://synthetic.example/game/#{id}", start_time: row['start_time'], status: 'final',
                          home_team_name: row.dig('home', 'source_name'), away_team_name: row.dig('away', 'source_name'),
                          home_team_score: 65, away_team_score: 64)
      GameExternalIdentity.associate!(game:, provider: 'cbbd', external_id: id.to_s)
      game
    end

    def self.local_sides(prior, row, game)
      %w[home away].each do |side|
        TeamGame.create!(side_values(prior, row, side).merge(game:, home: side == 'home'))
      end
    end

    def self.side_values(prior, row, side)
      team = Team.find_by!(school: row.dig(side, 'source_name'))
      values = row.fetch(side).fetch('stats').transform_values { |stat| stat['value'] }
      values.merge(team:, team_season: prior.team_seasons.find_by!(team:))
    end

    def observation(fixture, prior, index)
      raw = raw_game(fixture, prior, index)
      boxes = CbbdFixture.observation_boxes(fixture, raw, index)
      Ingestion::Cbbd::Normalizer.new({ 'raw' => raw, 'provenance' => { 'id' => "game-#{index}" } }, boxes).call
    end

    def raw_game(fixture, prior, index)
      home, away, date = CbbdFixture.game_position(index)
      labels = CbbdFixture.team_labels(@state.teams, home, away)
      fixture.fetch('games').first.merge('id' => index + 1, 'season' => prior.year, 'startDate' => date,
                                         'homeTeamId' => (home + 1) * 10, 'awayTeamId' => (away + 1) * 10).merge(labels)
    end

    def self.team_labels(teams, home, away)
      { 'homeTeam' => teams[home].school, 'awayTeam' => teams[away].school }
    end

    def self.game_position(index)
      home = index * 2 % 365
      away = (home + 1 + (index / 365)) % 365
      date = "#{(Date.new(2024, 11, 1) + (index / 182)).iso8601}T23:00:00Z"
      [home, away, date]
    end

    def self.observation_boxes(fixture, raw, index)
      fixture['boxes'].each_with_index.map do |box, side|
        ids = side.zero? ? raw.values_at('homeTeamId', 'awayTeamId') : raw.values_at('awayTeamId', 'homeTeamId')
        { 'raw' => box.merge('gameId' => index + 1, 'season' => raw['season'], 'startDate' => raw['startDate'],
                             'teamId' => ids[0], 'opponentId' => ids[1]),
          'provenance' => { 'id' => "box-#{index}-#{side}" } }
      end
    end
  end
end
