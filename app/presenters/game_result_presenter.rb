# frozen_string_literal: true

require 'delegate'

# Public result values only; canonical game eligibility is never changed by presentation.
class GameResultPresenter < SimpleDelegator
  # Missing source outcomes use normal availability text, with no private error state.
  class UnavailableResult < SimpleDelegator
    def status = 'result_unavailable'
    def status_string = 'Result unavailable'
  end

  # Ordinary participant names, scores and box values, without any operational metadata.
  Values = Data.define(:home_team_name, :away_team_name, :home_team_score, :away_team_score, :home_team_game, :away_team_game)
  delegate :home_team_name, :away_team_name, :home_team_score, :away_team_score, :home_team_game, :away_team_game, to: :result

  def initialize(game, source_observation:)
    super(game)
    @source = source_observation.normalized_payload
    @result = Values.new(home_team_name: @source.dig('home', 'name'), away_team_name: @source.dig('away', 'name'),
                         home_team_score: @source.dig('home', 'score'), away_team_score: @source.dig('away', 'score'),
                         home_team_game: source_side('home'), away_team_game: source_side('away'))
  end

  def self.wrap(games)
    games = games.to_a
    sources = GameIngestionIssue.unresolved.where(game_id: games.map(&:id), category: %w[participants missing_result])
                                .includes(:latest_observation).order(:id).index_by(&:game_id)
    games.map do |game|
      source = sources[game.id]&.latest_observation
      display(game, source)
    end
  end

  def self.display(game, source)
    return new(game, source_observation: source) if source && displayable?(source)
    return UnavailableResult.new(game) if source && game.scheduled? && game.schedule_date < Game.current_schedule_date

    game
  end

  def self.displayable?(observation)
    status, completed, home, away = observation.normalized_payload.values_at('source_status', 'source_completed', 'home', 'away')
    scores = [home['score'], away['score']]
    status == 'final' && completed == true && scores.all?(Integer) && scores.uniq.size == 2
  end

  def completed? = true
  def final? = true
  def status = 'final'
  def status_string = 'Final'
  def historical_prediction(**) = nil
  def current_prediction(**) = nil
  def current_bet_recommendations = []
  def current_prediction_unavailable_reason(**) = nil

  private

  attr_reader :result

  def source_side(label)
    side = TeamGame.new(@source.fetch(label).fetch('stats').slice(*Ingestion::GameObservation::STAT_KEYS.map(&:to_s)))
    link_side(side, label)
    side
  end

  def link_side(side, label)
    original = __getobj__.public_send("#{label}_team_game")
    return unless original && __getobj__.public_send("#{label}_team_name") == @source.dig(label, 'name')

    side.team = original.team
    side.team_season = original.team_season
  end
end
