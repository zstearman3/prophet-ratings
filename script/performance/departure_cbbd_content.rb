# frozen_string_literal: true

module OffseasonPerformance
  # Synthetic source shape matches the annual CBBD contract without network or new domain identities.
  class DepartureCbbdContent
    def self.plan
      Content.plan.merge('provider' => 'cbbd', 'schema' => Departures::CbbdDataset::VERSION,
                         'extraction_version' => Departures::CbbdDataset::REPORTED_TOTALS_EXTRACTION,
                         'scope_evidence' => 'Synthetic final regular and postseason evidence', 'max_requests' => 5, 'retries' => 0)
    end

    def response(uri)
      rows = response_rows(uri)
      { status: 200, body: JSON.generate(rows), headers: {} }
    end

    def response_rows(uri)
      scope = URI.decode_www_form(uri.query).to_h['seasonType']
      case uri.path
      when '/draft/picks' then picks
      when '/stats/player/season' then players(scope)
      when '/stats/team/season' then teams(scope)
      else raise 'Unexpected departure benchmark endpoint'
      end
    end

    def picks
      (1..60).map do |pick|
        id = self.class.athlete(pick, pick == 2 ? 1 : 0)
        { 'year' => 2025, 'overall' => pick, 'round' => (pick <= 30 ? 1 : 2), 'pick' => ((pick - 1) % 30) + 1,
          'name' => "Synthetic Player #{id}", 'athleteId' => id,
          'sourceTeamCollegeId' => pick, 'sourceTeamLocation' => school(pick) }
      end
    end

    def players(scope)
      games = self.class.games(scope)
      (1..Content::TEAMS).flat_map { |team| team_players(team, games) }
    end

    def team_players(team, games)
      (0...Content::PLAYERS).map { |player| player_row(team, player, games) }
    end

    def player_row(team, player, games)
      id = self.class.athlete(team, player)
      { 'season' => 2025, 'athleteId' => id, 'name' => "Synthetic Player #{id}", 'teamId' => team,
        'team' => school(team), 'games' => games, 'minutes' => 20.5,
        'points' => player.zero? ? 0 : 100 }
    end

    def teams(scope)
      games = self.class.games(scope)
      (1..Content::TEAMS).map do |team|
        { 'season' => 2025, 'teamId' => team, 'team' => school(team), 'games' => games, 'totalMinutes' => games * 40,
          'teamStats' => { 'points' => { 'total' => (Content::PLAYERS - 1) * 100 } } }
      end
    end

    def self.athlete(team, player)
      team == 2 && player.zero? ? 1 : ((team - 1) * Content::PLAYERS) + player + 1
    end

    def self.games(scope)
      { 'regular' => 30, 'postseason' => 2 }.fetch(scope)
    end

    def school(team)
      format('Synthetic University %03d', team)
    end
  end
end
