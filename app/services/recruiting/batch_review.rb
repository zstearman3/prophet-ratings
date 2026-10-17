# frozen_string_literal: true

module Recruiting
  # Saves draft mappings and publishes a preview-bound revision without operator files or hashes.
  class BatchReview
    def initialize(batch)
      @batch = batch
    end

    def report
      DatabaseBundle.new(batch, batch.season).report
    end

    def review_key
      metadata = batch.attributes.except('extract_bytes', 'snapshot_bytes')
      Departures::Contract.digest([metadata, batch.entries.order(:id).map(&:attributes), Team.order(:id).pluck(:id, :school),
                                   profile_state, latest_revision&.id])
    end

    def save(attributes)
      batch.with_lock do
        validate_draft(attributes)
        save_entries(attributes.fetch('rows', {}))
      end
    end

    def publish(attributes, reviewer:)
      Season.with_ratings_lock do
        batch.season.with_lock do
          batch.with_lock { publish_locked(attributes, reviewer) }
        end
      end
    end

    def self.validate_row_keys(rows, keys)
      return if rows.any? && (rows.keys - keys).empty?

      raise ArgumentError, 'Save must include known recruiting rows from this batch.'
    end

    private

    attr_reader :batch

    def profile_state
      batch.season.team_seasons.includes(:team_offseason_profile).order(:id).map do |row|
        OffseasonInputs::Import.profile_before(row)
      end
    end

    def latest_revision
      OffseasonInputRevision.where(season: batch.season, kind: 'recruiting').order(:id).last
    end

    def validate_draft(attributes)
      batch.require_draft
      raise ArgumentError, 'Recruiting review changed; reload and review again.' unless attributes['review_key'] == review_key
    end

    def save_entries(rows)
      entries = batch.entries.order(:id).index_by { |entry| entry.id.to_s }
      self.class.validate_row_keys(rows, entries.keys)

      rows.each { |id, attributes| entries.fetch(id).save_mapping(attributes) }
    end

    def publish_locked(attributes, reviewer)
      return batch.revision if batch.status == 'published'

      validate_draft(attributes)
      raise ArgumentError, 'Confirm that you reviewed the recruiting rows and partial coverage.' unless attributes['confirm'] == '1'

      save_entries(attributes.fetch('rows')) if attributes.key?('rows')
      publish_inputs(reviewer)
    end

    def publish_inputs(reviewer)
      batch.update!(reviewed_by: reviewer, reviewed_at: Time.current)
      prepare_team_seasons
      apply_publication
      batch.update!(status: 'published', revision: latest_revision)
      batch.revision
    end

    def apply_publication
      publication.apply_preview
    end

    def prepare_team_seasons
      batch.entries.where(excluded: false).where.not(team_id: nil).distinct.pluck(:team_id).each do |id|
        TeamSeason.find_or_create_by!(season: batch.season, team_id: id)
      end
    end

    def publication
      target = batch.season
      payload = DatabaseBundle.new(batch, target).call
      OffseasonInputs::Import.new(season: target, kind: 'recruiting', paths: { recruiting_batch_id: batch.id },
                                  publication: publication_metadata(payload))
    end

    def publication_metadata(payload)
      { version: "recruiting-batch-#{batch.id}", reason: 'Manual Review', predecessor_id: latest_revision&.id,
        input_hash: Departures::Contract.digest(payload) }
    end
  end
end
