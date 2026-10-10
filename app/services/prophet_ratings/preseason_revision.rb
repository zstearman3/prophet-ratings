# frozen_string_literal: true

module ProphetRatings
  # Deliberate publication of reviewed corrections; normal initialization still reuses captures.
  class PreseasonRevision < PreseasonInitializer
    def preview
      season.with_lock(requires_new: true) { build_preview }
    end

    def call(preview_key:)
      Season.with_ratings_lock do
        season.with_lock(requires_new: true) do
          apply_reviewed_preview(build_preview, preview_key)
        end
      end
    end

    private

    def apply_reviewed_preview(report, key)
      self.class.validate_preview_key(report, key)
      publish_revision(report)
      report
    end

    def build_preview
      validate_publication
      validate_revision_identity
      rows = preview_rows
      preview_report(rows, reviewed_baselines(rows))
    end

    def reviewed_baselines(rows)
      validate_existing_captures(rows)
      baselines = self.class.proposed_baselines(rows)
      validate_legacy_forecasts(baselines)
      baselines
    end

    def preview_report(rows, baselines)
      report = {
        season_id: season.id, start_date: season.start_date, end_date: season.end_date,
        participation_review: season.participation_review, model_version: ratings_config_version.name,
        model_version_id: ratings_config_version.id, previous_revision: season.preseason_revision&.name,
        included_team_ids: rows.pluck(:team_id), teams: rows,
        baselines: { before: season.attributes.slice(*baselines.keys), after: baselines }
      }
      report.merge(preview_key: Digest::SHA256.hexdigest(self.class.canonical_json(report.as_json).to_json))
    end

    def validate_revision_identity
      SeasonParticipationReview.new(season).validate
      unless season.rating_team_seasons.exists?
        raise ArgumentError,
              'No included teams; prepare and review season participants before revision.'
      end

      return unless version_used? && season.preseason_revision_id != ratings_config_version.id

      raise ArgumentError, 'This version already has preseason outputs; publish/select a new immutable MODEL_VERSION for corrections.'
    end

    def preview_rows
      calculator = PreseasonRatingsCalculator.new(season, ratings_config_version: ratings_config_version)
      season.rating_team_seasons.order(:team_id).map do |row|
        row.team_offseason_profile&.validate_revision_evidence
        inputs = calculator.preview_inputs(row).as_json
        self.class.preview_row(row, inputs, ratings_config_version.config)
      end
    end

    def version_used?
      season.team_rating_snapshots.exists?(ratings_config_version:) ||
        PreseasonPrior.exists?(team_season: season.team_seasons, ratings_config_version:)
    end

    def publish_revision(report)
      report.fetch(:teams).each { |row| capture_reviewed_prior(row) }
      initialize_ratings
      publish
      season.update!(preseason_revision: ratings_config_version)
    end

    def capture_reviewed_prior(row)
      team_season_id, inputs, outputs = row.values_at(:team_season_id, :inputs, :outputs_after)
      PreseasonPrior.find_or_create_by!(team_season_id:, ratings_config_version:) do |prior|
        prior.assign_attributes(inputs:, outputs:)
      end
    end

    # JSONB changes hash key order on load; preview identity must survive process/record reloads.
    public_class_method def self.canonical_json(value)
      transform = method(:canonical_json)
      case value
      when Hash then value.sort.to_h.transform_values(&transform)
      when Array then value.map(&transform)
      else value
      end
    end

    public_class_method def self.preview_row(row, inputs, config)
      prior = row.preseason_prior
      {
        team_id: row.team_id, team_season_id: row.id, added: prior.blank?,
        profile_before: prior&.inputs&.fetch('profile', nil), profile_after: inputs['profile'],
        outputs_before: prior&.outputs, outputs_after: PreseasonPriorFormula.new(inputs, config).call,
        inputs: inputs
      }
    end

    public_class_method def self.validate_preview_key(report, key)
      return if report.fetch(:preview_key).eql?(key)

      raise ArgumentError, 'Revision inputs changed or preview key is missing; rerun season:revise_preseason preview and review it.'
    end

    def validate_existing_captures(rows)
      captures = PreseasonPrior.where(team_season: season.team_seasons, ratings_config_version: ratings_config_version)
      return unless captures.exists?
      return if captures.count == rows.size && rows.all? { |row| self.class.matching_capture?(captures, row) }

      raise ArgumentError, 'Published revision inputs/coverage changed; preserve its captures and select a new MODEL_VERSION.'
    end

    public_class_method def self.matching_capture?(captures, row)
      capture = captures.find_by(team_season_id: row.fetch(:team_season_id))
      capture && capture.inputs == row.fetch(:inputs) && capture.outputs == row.fetch(:outputs_after)
    end

    public_class_method def self.proposed_baselines(rows)
      outputs = rows.pluck(:outputs_after)
      { 'average_efficiency' => 'preseason_adj_offensive_efficiency', 'average_pace' => 'preseason_adj_pace' }.transform_values do |stat|
        average_output(outputs, stat)
      end
    end

    public_class_method def self.average_output(outputs, stat)
      (outputs.sum { |values| values.fetch(stat) } / outputs.size).round(3)
    end

    def validate_legacy_forecasts(baselines)
      return unless legacy_forecasts?
      return if baselines.all? { |key, value| season[key] == value }

      raise ArgumentError, 'Legacy forecasts depend on mutable baselines; ' \
                           'review/resolve their provenance before publishing changed baselines.'
    end

    def legacy_forecasts?
      season.predictions.where("calculation_context ->> 'contract_version' IS DISTINCT FROM '1'").exists?
    end

    def validate_prediction_baselines
      # Contract 1 forecasts replay their own anchors; legacy forecasts retain the normal guard.
      super if legacy_forecasts?
    end
  end
end
