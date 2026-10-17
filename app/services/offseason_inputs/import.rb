# frozen_string_literal: true

module OffseasonInputs
  # Explicit, preview-bound publication of evidence only. No ratings or forecasts are touched.
  class Import
    POINTERS = { 'recruiting' => 'recruiting_revision_id', 'departures' => 'departure_revision_id' }.freeze

    def initialize(season:, kind:, paths:, publication:)
      @season = season
      @kind = kind
      @paths = paths
      @publication = publication.stringify_keys
    end

    def preview
      @season.with_lock(requires_new: true) { build_preview }
    end

    def call(preview_key:)
      @season.with_lock(requires_new: true) do
        report = build_preview
        self.class.validate_preview(report, preview_key)

        publish(report)
        report
      end
    end

    def apply_preview
      call(preview_key: preview.fetch('preview_key'))
    end

    def self.validate_preview(report, key)
      Departures::Contract.check!(report.fetch('preview_key') == key, 'Inputs or profiles changed; review a fresh preview')
    end

    def self.profile_before(membership)
      { 'team_id' => membership.team_id, 'team_season_id' => membership.id,
        'profile' => membership.team_offseason_profile&.attributes }
    end

    def self.update_profile(membership, pointer, revision)
      profile = membership.team_offseason_profile || membership.build_team_offseason_profile
      profile.update!(pointer => revision.id)
    end

    private

    def build_preview
      payload = load_payload
      input_hash = Departures::Contract.digest(payload)
      validate_publication(input_hash)
      report = { 'season_id' => @season.id, 'target_year' => @season.year, 'kind' => @kind, 'publication' => @publication,
                 'input_hash' => input_hash, 'payload' => payload, 'profiles_before' => profiles_before }
      report.merge('preview_key' => Departures::Contract.digest(report))
    end

    def load_payload
      return Recruiting::DatabaseBundle.new(RecruitingBatch.find(@paths.fetch(:recruiting_batch_id)), @season).call if @kind == 'recruiting'

      raise ArgumentError, 'Unsupported offseason input kind' unless @kind == 'departures'

      DepartureBundle.new(@paths, @season).call
    end

    def validate_publication(input_hash)
      validate_fields(input_hash)

      existing = revisions.find_by(input_hash:)
      return validate_repeat(existing) if existing

      raise ArgumentError, 'VERSION already exists; use a deliberate successor' if revisions.exists?(version: @publication.fetch('version'))

      validate_predecessor
    end

    def validate_fields(input_hash)
      Departures::Contract.text!(@publication.fetch('version'), 'VERSION')
      Departures::Contract.text!(@publication.fetch('reason'), 'REASON')
      raise ArgumentError, "INPUT_HASH must pin reviewed evidence: #{input_hash}" unless @publication.fetch('input_hash') == input_hash
    end

    def validate_repeat(existing)
      expected = existing.attributes.slice('version', 'reason', 'predecessor_id')
      return if @publication.slice(*expected.keys) == expected

      raise ArgumentError,
            'Identical inputs already imported with another publication identity'
    end

    def validate_predecessor
      latest = revisions.order(:id).last
      return if @publication['predecessor_id'] == latest&.id

      raise ArgumentError, 'Correction requires the latest PREDECESSOR_ID; review its evidence and supply a reason'
    end

    def revisions
      OffseasonInputRevision.where(season: @season, kind: @kind)
    end

    def profiles_before
      converter = self.class
      @season.team_seasons.order(:team_id).map { |membership| converter.profile_before(membership) }
    end

    def publish(report)
      input_hash = report.fetch('input_hash')
      revision = revisions.find_by(input_hash:)
      return if revision # An exact retry never re-selects older evidence after a later correction.

      revision = create_revision(report.fetch('payload'), input_hash)
      link_profiles(revision)
    end

    def link_profiles(revision)
      writer = self.class
      pointer = POINTERS.fetch(@kind)
      @season.team_seasons.order(:team_id).each { |membership| writer.update_profile(membership, pointer, revision) }
    end

    def create_revision(payload, input_hash)
      revisions.create!(@publication.slice('version', 'reason', 'predecessor_id').merge(
                          input_hash:, dataset_hash: payload.fetch('dataset_hash'),
                          review_hash: payload.fetch('review_hash'), payload:
                        ))
    end
  end
end
