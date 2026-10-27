# frozen_string_literal: true

# Setup reads saved certificates and scalar pointers; source replay belongs to validation workers.
class DepartureProgress
  def initialize(season)
    @season = season
    @revision = OffseasonInputRevision.where(season:, kind: 'departures').select(:id).order(:id).last
    @batch = DepartureBatch.where(season:).select(:id, :status, :revision_id).order(:id).last
  end

  def call
    OffseasonSetupProgress::Step.new(key: 'departures', label: 'Review departures',
                                     status: current? ? 'complete' : 'needs_review', last_result: "#{approval_summary} #{batch_summary}",
                                     next_action: 'Review departure batches and validation; select the model in preseason preview.')
  end

  private

  attr_reader :season, :revision, :batch

  def approval_summary
    revision ? "Departure revision ##{revision.id} is retained." : 'No reviewed departure revision is stored.'
  end

  def batch_summary
    return 'No departure preparation is stored.' unless batch

    acquisition = batch.acquisitions.order(id: :desc).pick(:status) || 'not requested'
    state = certificate&.progress_status || 'needed'
    "Latest departure batch ##{batch.id}: #{batch.status}; acquisition #{acquisition}; validation #{state}."
  end

  def certificate
    @certificate ||= DepartureValidation.where(departure_batch_id: batch&.id).order(:id).last
  end

  def current?
    id = revision&.id
    return false unless id && batch&.revision_id == id && batch.status == 'published'
    return false unless certificate&.status == 'published' && certificate.offseason_input_revision_id == id && certificate.current?

    pointers_current?
  end

  def pointers_current?
    members = season.team_seasons
    members.order(:team_id).pluck(:team_id) == certificate.proposals.order(:team_id).pluck(:team_id) &&
      TeamOffseasonProfile.where(team_season_id: members.select(:id), departure_revision_id: revision.id).count == members.count
  end
end
