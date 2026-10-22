# frozen_string_literal: true

# Approval and the latest attempt remain separate, including failures after publication.
class DepartureProgress
  def initialize(season)
    @season = season
    @revision = OffseasonInputRevision.where(season:, kind: 'departures').order(:id).last
    @batch = DepartureBatch.where(season:).order(:id).last
  end

  def call
    OffseasonSetupProgress::Step.new(key: 'departures', label: 'Review departures',
                                     status: current? ? 'complete' : 'needs_review', last_result: "#{approval_summary} #{batch_summary}",
                                     next_action: 'Review departure batches and coverage; select the model in preseason preview.')
  end

  private

  attr_reader :season, :revision, :batch

  def approval_summary
    revision ? "Departure revision ##{revision.id} is retained." : 'No reviewed departure revision is stored.'
  end

  def batch_summary
    return 'No departure preparation is stored.' unless batch

    "Latest departure batch ##{batch.id}: #{batch.status}; acquisition #{batch.attempt&.status || 'not requested'}."
  end

  def current?
    return false unless revision && batch&.revision_id == revision.id && batch.status == 'published'

    pointers_current? && report_current?
  rescue ArgumentError, KeyError
    false
  end

  def pointers_current?
    id = revision.id
    rows = season.team_seasons.includes(:team_offseason_profile).to_a
    rows.map(&:team_id).sort == revision.payload.fetch('team_inputs').keys.map(&:to_i).sort &&
      rows.all? { |row| row.team_offseason_profile&.departure_revision_id == id }
  end

  def report_current?
    report = Departures::BatchReview.new(batch).report
    report.fetch('errors').empty? && report.except('gaps', 'errors',
                                                   'reviewed_revision') == revision.payload.fetch('report').except('reviewed_revision')
  end
end
