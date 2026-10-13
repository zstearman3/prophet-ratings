# frozen_string_literal: true

require 'base64'

module OffseasonInputs
  # Rebuilds the exact mapping approval from saved evidence and stored identities.
  class RecruitingBundle
    def initialize(paths, season)
      @paths = paths
      @season = season
      @dataset = Recruiting::Dataset.load(paths.fetch(:dataset_dir))
    end

    def call
      report = Recruiting::Preview.new(@dataset, @season).call
      self.class.validate_rows(report)
      reviewed = validated_review(report)
      { 'kind' => 'recruiting', 'dataset_hash' => report.fetch('dataset_revision'),
        'review_hash' => Departures::Contract.digest(reviewed), 'dataset' => @dataset.manifest.as_json,
        'review' => reviewed, 'report' => reviewed, 'evidence' => evidence, 'team_inputs' => team_inputs(report) }
    end

    def self.validate_rows(report)
      fatal = report.fetch('rows').flat_map { |row| row.fetch('errors') + row.fetch('exclusions').grep(/Duplicate|Ambiguous/) }
      raise ArgumentError, "Resolve recruiting conflicts: #{fatal.uniq.join('; ')}" if fatal.any?
    end

    def self.eligible_rows(report)
      report.fetch('rows').select { |row| row.fetch('exclusions').empty? }.index_by { |row| row.fetch('team_id') }
    end

    def self.input(row)
      points = row&.dig('values', 'class_points')
      { 'status' => point_status(points), 'class_points' => points,
        'units' => { 'class_points' => '247_recruit_composite_class_points' },
        'row' => row, 'reason' => row ? 'reviewed_source_row' : 'omitted_or_unresolved_team' }
    end

    def self.point_status(points)
      return 'unknown' unless points

      BigDecimal(points).zero? ? 'verified_zero' : 'verified_points'
    end

    def self.approve(report, reviewed)
      Recruiting::MappingReview.new(report).approve(reviewed.merge(reviewed.fetch('approval')))
    end

    private

    def validated_review(report)
      reviewed = JSON.parse(File.read(@paths.fetch(:review_path)))
      approved = self.class.approve(report, reviewed).as_json
      raise ArgumentError, 'Reviewed recruiting report changed; review a fresh preview' unless reviewed == approved

      reviewed
    end

    def evidence
      { 'original_base64' => retained_file('original.json', 'extract_sha256'),
        'snapshot_base64' => retained_file('snapshot', 'snapshot_sha256') }
    end

    def retained_file(name, hash_key)
      bytes = File.binread(File.join(@paths.fetch(:dataset_dir), name))
      Departures::Contract.check!(Digest::SHA256.hexdigest(bytes) == @dataset.manifest.fetch(hash_key),
                                  'Recruiting evidence changed during preview')
      Base64.strict_encode64(bytes)
    end

    def team_inputs(report)
      converter = self.class
      rows = converter.eligible_rows(report)
      @season.team_seasons.order(:team_id).pluck(:team_id).to_h { |id| [id.to_s, converter.input(rows[id])] }
    end
  end
end
