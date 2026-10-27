# frozen_string_literal: true

# An explicit choice between two pending CBBD schedule entries; the original evidence remains immutable.
class GameScheduleReview < ApplicationRecord
  belongs_to :season
  belongs_to :schedule_refresh_run
  belongs_to :game
  belongs_to :source_observation, class_name: 'GameObservation'
  belongs_to :prior_observation, class_name: 'GameObservation'
  belongs_to :reviewed_by, class_name: 'User'
  validates :choice, inclusion: { in: %w[existing incoming] }
  validates :reason, inclusion: { in: ['Approved by admin'] }
  validates :selected_external_id, :ignored_external_id, :ignored_fingerprint, :comparison_fingerprint, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Schedule reviews are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Schedule reviews are immutable' }

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON::State.new(sort_keys: true).generate(value.as_json))
  end

  def self.payload_fingerprint(payload)
    normalized = Ingestion::GameObservation.new(payload).validate.data
    digest(normalized.except(:captured_at, :payload_digest, :raw_payload))
  end

  def self.participants_for(resolution)
    resolution.memberships.map { |membership| [membership&.team_id, membership&.id] }
  end

  def self.schedule_values(attributes)
    time = attributes.fetch('start_time')
    date = Game.schedule_date_for(time)
    timestamp = time.iso8601
    attributes.slice('venue_name', 'venue_source', 'venue_confidence', 'venue_type', 'neutral').merge(
      'start_time' => timestamp, 'schedule_date' => date.iso8601,
      'tip_time' => time == Game.schedule_time_for(date) ? nil : timestamp
    )
  end

  def current?(candidate, resolution)
    candidate&.id == game_id && candidate.season_id == season_id &&
      participants == GameScheduleReview.participants_for(resolution) &&
      GameScheduleReview.stored_participants(candidate) == participants && identities_current?
  end

  private

  def identities_current?
    GameExternalIdentity.active.exists?(game_id:, provider: 'cbbd', external_id: selected_external_id) &&
      GameExternalIdentity.where.not(superseded_at: nil).exists?(game_id:, provider: 'cbbd', external_id: ignored_external_id)
  end

  public_class_method def self.stored_participants(candidate)
    [candidate.home_team_game, candidate.away_team_game].map { |side| [side&.team_id, side&.team_season_id] }
  end
end
