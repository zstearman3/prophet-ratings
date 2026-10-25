# frozen_string_literal: true

require 'base64'

module OffseasonInputs
  # Parses retained bytes again; a caller-supplied hash alone never authenticates production.
  class DepartureBundle
    def initialize(paths, season)
      @paths = paths
      @season = season
    end

    def call
      dataset = replay
      review = reviewed_file(dataset)

      report = Departures::Preview.new(dataset:, review:).call
      self.class.validate_conflicts(dataset, report)
      { 'kind' => 'departures', 'dataset_hash' => dataset.fetch('dataset_revision'),
        'review_hash' => Departures::Contract.digest(review), 'dataset' => dataset, 'review' => review,
        'report' => report, 'evidence' => evidence(dataset), 'team_inputs' => team_inputs(report) }
    end

    def self.validate_conflicts(dataset, report)
      Departures::Contract.check!(dataset.fetch('failures').empty?, 'Resolve failed departure sources before publication')
      conflicts = report.fetch('status_counts').fetch('conflicting_evidence', 0)
      Departures::Contract.check!(conflicts.zero?, 'Resolve conflicting departure evidence before publication')
    end

    private

    def reviewed_file(dataset)
      raise ArgumentError, 'Departure target season mismatch' unless dataset.fetch('target_year') == @season.year

      review = JSON.parse(File.read(@paths.fetch(:review_path)))
      raise ArgumentError, 'Require a reviewed departure file' if review.empty?

      review
    end

    def replay
      @paths[:departure_attempt_id] ? database_replay : file_replay
    end

    def file_replay
      directory = @paths.fetch(:capture_dir)
      manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
      dataset = Departures::AnnualDataset.new(manifest:, directory:).call
      validate_replay(dataset)
      dataset
    end

    def database_replay
      attempt = DepartureAcquisition.find(@paths.fetch(:departure_attempt_id))
      Departures::RetainedEvidence.new(attempt).verified_dataset(attempt.plan)
    end

    def validate_replay(dataset)
      saved = JSON.parse(File.read(@paths.fetch(:dataset_path)))
      Departures::Contract.check!(saved == dataset, 'Saved departure dataset differs from source replay')
    end

    def evidence(dataset)
      return DepartureAcquisition.find(@paths.fetch(:departure_attempt_id)).evidence if @paths[:departure_attempt_id]

      Departures::RetainedEvidence.sources(dataset).to_h do |source|
        [source.fetch('id'), { 'snapshot_base64' => retained_snapshot(source) }]
      end
    end

    def retained_snapshot(source)
      location = source['snapshot_location']
      return unless location

      sha = source.fetch('snapshot_sha256')
      self.class.validate_location(location, sha)
      Base64.strict_encode64(retained_bytes(location, sha))
    end

    public_class_method def self.validate_location(location, sha)
      Departures::Contract.check!(["#{sha}.html", "#{sha}.json"].include?(location) && sha.match?(/\A[a-f0-9]{64}\z/),
                                  'Invalid snapshot location')
    end

    def retained_bytes(location, sha)
      bytes = File.binread(File.join(@paths.fetch(:capture_dir), location))
      Departures::Contract.check!(Digest::SHA256.hexdigest(bytes) == sha, 'Snapshot hash mismatch')

      bytes
    end

    def team_inputs(report)
      reports = report.fetch('teams').index_by { |row| row.fetch('team_id') }
      @season.team_seasons.order(:team_id).pluck(:team_id).to_h do |id|
        [id.to_s, reports.fetch(id).merge('units' => Departures::ProductionStint::UNITS,
                                          'loss_share_unit' => 'fraction_of_team_points')]
      end
    end
  end
end
