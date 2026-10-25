# frozen_string_literal: true

require 'json'
require 'digest'
require 'base64'
require 'date'

module OffseasonPerformance
  # Repeated dated observations model retained evidence, not extra teams or stronger ratings.
  class Content
    TEAMS = 365
    PLAYERS = 15
    CAPTURES = 22
    TIME = '2025-06-30T12:00:00Z'
    DRAFT_ROUNDS = { 'First Round' => (1..30), 'Second Round' => (31..60) }.freeze
    attr_reader :scale

    def initialize(scale:)
      raise ArgumentError, 'scale must be 1 or 2' unless [1, 2].include?(scale)

      @scale = scale
    end

    def school(index)
      format('Synthetic University %03d', index + 1)
    end

    def draft
      body = DRAFT_ROUNDS.map { |round, picks| draft_round(round, picks) }.join
      "<h1>2025 NBA Draft Results Picks 1-60</h1>#{body}"
    end

    def draft_round(round, picks)
      players = picks.map { |pick| draft_pick(pick) }.join
      "<h2>#{round}</h2>#{players}"
    end

    def draft_pick(pick)
      number = pick.to_s
      "<p>#{number}. Synthetic Pro Club draft <a href='/draft/2025/prospects/player-#{number}'>Player #{number}</a> " \
        "(#{school(number.to_i - 1)})</p>"
    end

    def self.totals(team, observation)
      rows = (0...PLAYERS).map do |player|
        # Player 1 has two independently reviewed school stints.
        athlete = team == 1 && player.zero? ? 1 : (team * PLAYERS) + player + 1
        "<tr><td><a href='/sports/mens-basketball/roster/athlete-#{athlete}'>Synthetic Player #{athlete}</a></td>" \
          "<td>32</td><td>#{300 + (player * 10)}</td><td>#{80 + (player * 5)}</td></tr>"
      end.join
      "<h1>2024-25 Men's Basketball Cumulative Statistics</h1><h2>Overall Totals</h2>" \
        "<p>Final archived observation #{observation + 1}; regular season and postseason included; exhibitions excluded.</p>" \
        '<table><thead><tr><th>Player</th><th>GP</th><th>MIN</th><th>PTS</th></tr></thead>' \
        "<tbody>#{rows}</tbody></table><table><tr><th>Total Points</th><td>1725</td></tr></table>"
    end

    def each_source
      return enum_for(:each_source) unless block_given?

      yield source('draft', 'nba_results', 'https://www.nba.com/news/2025-nba-draft-order'), draft
      school_sources.each { |pair| yield(*pair) }
    end

    def school_sources
      observations = CAPTURES * scale
      (0...(TEAMS * observations)).lazy.map do |index|
        team, observation = index.divmod(observations)
        school_source(team, observation)
      end
    end

    def school_source(team, observation)
      id = "school-#{team}-#{observation}"
      url = "https://synthetic-#{team}.example/stats/2024-25?archive=#{observation}"
      captured = "#{(Date.new(2025, 6, 30) + observation).iso8601}T12:00:00Z"
      [source(id, 'sidearm_totals', url).merge('team_name_source' => school(team), 'captured_at' => captured),
       self.class.totals(team, observation)]
    end

    def source(id, type, url)
      { 'id' => id, 'type' => type, 'url' => url, 'scope' => 'overall_season_including_postseason_excluding_exhibitions',
        'scope_evidence' => 'Synthetic archived final overall roster totals, including postseason and excluding exhibitions',
        'captured_at' => TIME, 'observed_at' => TIME, 'source_as_of' => TIME, 'http_status' => 200, 'snapshot_kind' => 'raw_html' }
    end

    def self.plan
      { 'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => (1..60).to_a }
    end

    def cardinalities
      captures = TEAMS * CAPTURES * scale
      { 'target_teams' => TEAMS, 'distinct_school_players' => (TEAMS * PLAYERS) - 1, 'draft_picks' => 60,
        'school_capture_observations' => captures, 'player_observations' => captures * PLAYERS,
        'historical_snapshots' => TEAMS * 165 * scale, 'cbbd_game_observations' => 10_000 * scale }
    end
  end
end
