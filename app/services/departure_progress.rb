# frozen_string_literal: true

# Progress uses a current retained certificate; visiting setup never replays raw departure evidence.
class DepartureProgress
  def initialize(season)
    @season = season
    @revision = OffseasonInputRevision.where(season:, kind: 'departures').select(:id, :input_hash).order(:id).last
    @batch = DepartureBatch.where(season:).select(:id, :status, :revision_id).order(:id).last
  end

  def call
    OffseasonSetupProgress::Step.new(key: 'departures', label: 'Review departures',
                                     status: current? ? 'complete' : 'needs_review', last_result: "#{approval_summary} #{batch_summary}",
                                     next_action: 'Review departure batches and validation; select the model in preseason preview.')
  end

  private

  def approval_summary
    @revision ? "Departure revision ##{@revision.id} is retained." : 'No reviewed departure revision is stored.'
  end

  def batch_summary
    return 'No departure preparation is stored.' unless @batch

    acquisition = @batch.acquisitions.order(id: :desc).pick(:status) || 'not requested'
    "Latest departure batch ##{@batch.id}: #{@batch.status}; acquisition #{acquisition}; validation #{certificate&.status || 'needed'}."
  end

  def certificate
    @certificate ||= DepartureValidation.where(departure_batch_id: @batch&.id).order(:id).last
  end

  def current?
    return false unless @revision && @batch&.revision_id == @revision.id && @batch.status == 'published'
    return false unless certificate&.current?

    verified_revision? && pointers_current?
  end

  def verified_revision?
    case certificate.status
    when 'published' then certificate.offseason_input_revision_id == @revision.id
    when 'ready' then historical_current?(certificate.choices)
    else false
    end
  end

  def historical_current?(choices)
    choices.values_at('historical_revision_id', 'historical_input_hash') == [@revision.id, @revision.input_hash]
  end

  def pointers_current?
    members = @season.team_seasons
    proposal_ids = certificate.proposals.order(:team_id).pluck(:team_id)
    members.order(:team_id).pluck(:team_id) == proposal_ids &&
      TeamOffseasonProfile.where(team_season_id: members.select(:id), departure_revision_id: @revision.id).count == members.count
  end
end
