# frozen_string_literal: true

require 'base64'

module Recruiting
  # Adapts reviewed table rows to the existing immutable offseason input contract.
  class DatabaseBundle
    def initialize(batch, season)
      @batch = batch
      @season = season
    end

    def report
      dataset = batch.dataset
      entries = batch.entries.order(:row_number).to_a
      validate_source(dataset, entries)
      Preview.new(dataset, season, rows: entries.map(&:review_row)).call
    end

    def call
      proposal = report
      validate_review(proposal)
      reviewed = approved_report(proposal)
      { 'kind' => 'recruiting', 'dataset_hash' => batch.dataset_revision,
        'review_hash' => Departures::Contract.digest(reviewed), 'dataset' => batch.dataset.manifest.as_json,
        'review' => reviewed, 'report' => reviewed, 'evidence' => evidence, 'team_inputs' => team_inputs(proposal) }
    end

    def self.source_values(row)
      row.slice('row_number', 'raw', 'errors').merge('values' => row.fetch('values', Extract::NUMERIC_FIELDS.index_with { nil }))
    end

    def self.verify_row(row, entry)
      expected = Departures::Contract.digest(source_values(row).as_json)
      actual = Departures::Contract.digest(source_values(entry.review_row).as_json)
      raise ArgumentError, 'Stored recruiting values changed; fetch a new batch.' unless expected == actual
    end

    def self.unresolved_rows(proposal)
      proposal.fetch('rows').select do |row|
        row['team_id'].blank? && row.fetch('exclusions').exclude?('Excluded by manual review')
      end
    end

    def self.validate_rows(report)
      fatal = report.fetch('rows').flat_map do |row|
        Row.review_errors(row) + row.fetch('exclusions').grep(/Duplicate|Ambiguous|Conflicting/)
      end
      raise ArgumentError, "Resolve recruiting conflicts: #{fatal.uniq.join('; ')}" if fatal.any?
    end

    def self.eligible_rows(report)
      report.fetch('rows').select { |row| row.fetch('exclusions').empty? }.index_by { |row| row.fetch('team_id') }
    end

    def self.input(row, units = '247_recruit_composite_class_points')
      points = row&.dig('values', 'class_points')
      { 'status' => point_status(points), 'class_points' => points,
        'units' => { 'class_points' => units },
        'row' => row, 'reason' => row ? 'reviewed_source_row' : 'omitted_or_unresolved_team' }
    end

    def self.point_status(points)
      return 'unknown' unless points

      BigDecimal(points).zero? ? 'verified_zero' : 'verified_points'
    end

    private

    attr_reader :batch, :season

    def validate_source(dataset, entries)
      rows = dataset.manifest.fetch('rows')
      raise ArgumentError, 'Stored recruiting rows do not match the capture; fetch a new batch.' unless rows.size == entries.size

      rows.zip(entries).each { |row, entry| self.class.verify_row(row, entry) }
    end

    def validate_batch
      raise ArgumentError, 'Recruiting batch belongs to another season.' unless batch.season_id == season.id

      batch.require_draft
      raise ArgumentError, 'Only a successful recruiting capture can be published.' unless batch.source_status == 'ok'
    end

    def validate_review(proposal)
      validate_batch
      validator = self.class
      validator.validate_rows(proposal)
      return unless validator.unresolved_rows(proposal).any?

      raise ArgumentError, 'Map or explicitly exclude every unresolved source row.'
    end

    def approved_report(proposal)
      reviewer = batch.reviewed_by
      raise ArgumentError, 'Recruiting approval requires a reviewer.' unless Extract.text?(reviewer)

      approved_at = batch.reviewed_at&.iso8601
      Extract.timestamp(approved_at)
      proposal.merge('review_status' => 'reviewed', 'approval' => { 'approved_by' => reviewer, 'approved_at' => approved_at })
    end

    def evidence
      { 'original_base64' => Base64.strict_encode64(batch.extract_bytes),
        'snapshot_base64' => Base64.strict_encode64(batch.snapshot_bytes) }
    end

    def team_inputs(proposal)
      converter = self.class
      rows = converter.eligible_rows(proposal)
      season.team_seasons.order(:team_id).pluck(:team_id).to_h do |id|
        [id.to_s, converter.input(rows[id], "#{batch.cbbd? ? 'cbbd' : '247'}_recruit_composite_class_points")]
      end
    end
  end
end
