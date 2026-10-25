# frozen_string_literal: true

# An immutable, exact-input exception to the scoring component identity, never a general validation bypass.
class GameScoringReview < ApplicationRecord
  belongs_to :season
  belongs_to :schedule_refresh_run
  belongs_to :source_observation, class_name: 'GameObservation'
  belongs_to :reviewed_by, class_name: 'User'
  has_many :observations, class_name: 'GameObservation', foreign_key: :scoring_review_id, inverse_of: :scoring_review,
                          dependent: :restrict_with_exception
  has_one :imported_observation, -> { where(accepted: true) }, class_name: 'GameObservation', foreign_key: :scoring_review_id,
                                                               inverse_of: :scoring_review, dependent: :restrict_with_exception
  has_one :game, through: :imported_observation
  validates :source_fingerprint, presence: true, uniqueness: true
  validates :reason, inclusion: { in: ['Approved by admin'] }
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Scoring reviews are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Scoring reviews are immutable' }

  def self.for_game(game)
    GameObservation.where(game:, accepted: true).where.not(scoring_review_id: nil).order(id: :desc).first&.scoring_review
  end

  def self.source_fingerprint(payload)
    Digest::SHA256.hexdigest(JSON.generate(canonical(fingerprint_fields(payload))))
  end

  def self.fingerprint_fields(payload)
    fields = payload.deep_stringify_keys.except('captured_at', 'payload_digest', 'raw_payload', 'scoring_review_id')
    fields.merge('home' => fields.fetch('home').except('field_availability'),
                 'away' => fields.fetch('away').except('field_availability'),
                 'start_time' => Ingestion::GameObservation.timestamp(fields['start_time']),
                 'source_updated_at' => Ingestion::GameObservation.timestamp(fields['source_updated_at']))
  end

  def self.canonical(value)
    case value
    when Hash then canonical_hash(value)
    when Array then value.map { |entry| canonical(entry) }
    else value
    end
  end

  def self.canonical_hash(value)
    value.sort.to_h { |key, entry| [key, canonical(entry)] }
  end

  def matches_payload?(payload)
    review_class = self.class
    persisted? && review_class.source_fingerprint(approved_payload) == review_class.source_fingerprint(payload)
  end

  def validate_payload(payload, resolution)
    return if matches_payload?(payload) && matches_resolution?(resolution)

    raise Ingestion::GameObservation::Invalid, 'Scoring approval does not match source values or participants'
  end

  def matches_resolution?(resolution)
    participants == self.class.participants_for(resolution)
  end

  def self.participants_for(resolution)
    Ingestion::GameObservation::SIDES.each_with_index.to_h do |label, index|
      [label.to_s, { 'team_id' => resolution.teams[index]&.id, 'team_season_id' => resolution.memberships[index]&.id }]
    end
  end

  def matches_game?(candidate)
    state = self.class.game_values(candidate)
    return false unless persisted? && matches_context?(state)

    expected = candidate.persisted? ? expected_sides : transient_sides
    state.fetch('sides') == expected
  end

  def validate_current(resolution)
    candidate = resolution.game
    candidate&.lock!
    resolution.validate_game(candidate) if candidate
    return if candidate && candidate.id == game&.id && matches_resolution?(resolution) && matches_game?(candidate)

    raise Ingestion::ObservationResolution::Held.new('conflict', 'reviewed_game_changed')
  end

  def self.game_values(candidate)
    { 'season_id' => candidate.season_id, 'start_time' => candidate.start_time,
      'schedule_date' => candidate.schedule_date.iso8601,
      'result' => candidate.attributes.slice('home_team_name', 'home_team_score', 'away_team_name', 'away_team_score'),
      'sides' => %w[home away].index_with { |label| game_side(candidate, label) } }
  end

  def self.game_side(candidate, label)
    side = candidate.public_send("#{label}_team_game")
    return unless side

    attributes = side.attributes
    attributes.slice('team_id', 'team_season_id').merge('name' => candidate.public_send("#{label}_team_name"),
                                                        'score' => candidate.public_send("#{label}_team_score"),
                                                        'stats' => attributes.slice(*Ingestion::GameObservation::STAT_KEYS.map(&:to_s)))
  end

  private

  def matches_context?(state)
    timestamp = approved_payload['start_time']
    state['season_id'] == season_id && state['schedule_date'] == approved_payload['schedule_date'] && state['result'] == expected_result &&
      (!timestamp || state['start_time'] == Time.iso8601(timestamp))
  end

  def expected_result
    approved_payload.slice('home', 'away').flat_map do |label, side|
      name, score = side.values_at('name', 'score')
      [["#{label}_team_name", name], ["#{label}_team_score", score]]
    end.to_h
  end

  def expected_sides
    participants.to_h do |label, identity|
      expected = identity['team_season_id'].present? ? approved_payload.fetch(label).slice('name', 'score', 'stats').merge(identity) : nil
      [label, expected]
    end
  end

  def transient_sides
    approved_payload.slice('home', 'away').transform_values do |side|
      side.slice('name', 'score', 'stats').merge('team_id' => nil, 'team_season_id' => nil)
    end
  end
end
