# frozen_string_literal: true

module ReadinessFixture
  def publish_readiness_fixture(season, model, row, admin)
    create(:team_alias, team: row.team, value: row.team.school)
    document = {
      'evidence' => 'Synthetic verified independent roster', 'reviewed_by' => 'Test operator',
      'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601, 'evidence' => 'Verified dates' },
      'teams' => [{ 'team_id' => row.team_id, 'status' => 'included', 'reason' => 'Verified independent' }],
      'membership_decisions' => [{ 'team_id' => row.team_id, 'choice' => 'independent' }], 'unresolved_identities' => []
    }
    SeasonParticipationReview.new(season).apply(document)
    PreseasonPublication.select_model(season, model)
    publication = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    PreseasonPublicationQueue.new(publication, actor: admin, fingerprint: publication.fingerprint, acknowledge: '1').call
    PreseasonPublicationExecution.new(publication).call
    raise publication.reload.error_message unless publication.status == 'published'
  end

  def save_readiness_review(season, admin, **)
    report = OffseasonReadiness.new(season).call
    OffseasonReadinessReview.record!(season, reviewer: admin, fingerprint: report.fetch('fingerprint'), acknowledge: '1', **)
  end
end
