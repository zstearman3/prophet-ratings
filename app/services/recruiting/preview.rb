# frozen_string_literal: true

module Recruiting
  # Exact canonical/alias matching is read-only and excludes all duplicate occurrences.
  class Preview
    def initialize(dataset, season, **options)
      @dataset = dataset
      @season = season
      @matches = options.fetch(:rows) { dataset.manifest.fetch('rows').map { |row| self.class.match(row) } }
    end

    def call
      validate_season
      review_rows
      payload = report
      payload.merge('mapping_revision' => Digest::SHA256.hexdigest(JSON.generate(payload)), 'review_status' => 'unreviewed')
    end

    def self.match(row)
      raw = row['raw']
      candidates = matching_ids(raw)
      row.merge('candidate_team_ids' => candidates, 'team_id' => unique_id(candidates),
                'exclusions' => Row.review_errors(row) + match_errors(candidates))
    end

    def self.matching_ids(raw)
      saved = CbbdIdentities.find(raw)
      return [saved.team_id] if saved

      raw.is_a?(Hash) ? candidate_ids(raw['team_label']) : []
    end

    def self.unique_id(candidates)
      candidates.first if candidates.one?
    end

    def self.match_errors(candidates)
      return ['Unmatched team: review canonical school or stored alias'] if candidates.empty?
      return ['Ambiguous team: review canonical/alias conflict'] if candidates.many?

      []
    end

    def self.candidate_ids(label)
      return [] unless Extract.text?(label)

      Team.matching_school_or_alias(label).ids
    end

    def self.identity(row, key)
      return row[key] if key == 'team_id'

      raw = row['raw']
      raw[key] if raw.is_a?(Hash)
    end

    def validate_season
      target = @dataset.extract.metadata.fetch('target_season')
      raise ArgumentError, 'Preview requires the explicit matching target season' unless @season.year == target
    end

    def review_rows
      @matches.each do |row|
        row['warnings'] = Row.review_warnings(row)
        self.class.validate_identity(row)
      end
      %w[team_label provider_team_id team_id].each { |key| exclude_duplicates(key) }
    end

    def self.validate_identity(row)
      return unless CbbdIdentities.conflict?(row['raw'], row['team_id'])

      row['exclusions'] |= ['Conflicting durable CBBD identity; cannot reassign a provider team']
    end

    def exclude_duplicates(key)
      matcher = self.class
      @matches.group_by { |row| matcher.identity(row, key) }.each do |identity, rows|
        matcher.exclude_group(key, identity, rows)
      end
    end

    def self.exclude_group(key, identity, rows)
      return unless identity.present? && rows.many?

      rows.each { |row| row['exclusions'] |= ["Duplicate/conflicting #{key}: #{identity}; exclude every occurrence"] }
    end

    def covered_ids
      @matches.select { |row| row['exclusions'].empty? }.pluck('team_id')
    end

    def point_rows
      classifier = self.class
      classifier.point_groups(@matches.group_by { |row| classifier.point_status(row) })
    end

    def self.point_status(row)
      return 'invalid' unless row.key?('values')
      return 'missing' if row.dig('raw', 'class_points').is_a?(NilClass)

      row.dig('values', 'class_points') || 'invalid'
    end

    def self.point_groups(groups)
      { 'missing_points_rows' => groups.fetch('missing', []).pluck('row_number'),
        'explicit_zero_rows' => groups.fetch('0.0', []).pluck('row_number'),
        'invalid_points_rows' => groups.fetch('invalid', []).pluck('row_number') }
    end

    def report
      ids = covered_ids
      {
        'dataset_revision' => @dataset.manifest.fetch('dataset_revision'), 'target_season' => @season.year,
        'source_status' => 'ok', 'coverage' => (@matches.empty? ? 'empty' : 'partial'),
        'extracted_rows' => @matches.size, 'eligible_rows' => ids.size, 'omitted_stored_team_ids' => Team.order(:id).ids - ids,
        'rows' => @matches
      }.merge(point_rows)
    end
  end
end
