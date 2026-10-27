# frozen_string_literal: true

module Admin
  # Human-facing labels for the saved departure evidence workflow.
  module DepartureBatchesHelper
    SOURCE_LABELS = { 'draft' => 'NBA draft selections', 'player-regular' => 'Regular-season player totals',
                      'team-regular' => 'Regular-season team totals', 'player-postseason' => 'Postseason player totals',
                      'team-postseason' => 'Postseason team totals' }.freeze

    FETCH_LABELS = { 'queued' => 'Fetch queued', 'running' => 'Fetch in progress', 'failed' => 'Fetch failed' }.freeze

    def departure_source_label(source)
      id = source.fetch('id')
      tag.span(SOURCE_LABELS.fetch(id, id))
    end

    def departure_stage(batch, attempt)
      return tag.span('Published inputs') if batch.status == 'published'
      return tag.span('Ready to fetch') unless attempt

      reviewed = Departures::DraftTeamReview.applicable?(batch) ? 'Review draft results and college teams' : 'Review players and publish'
      tag.span(FETCH_LABELS.fetch(attempt.status, reviewed))
    end

    def departure_review_label(value)
      labels = request.get_header('prophet.departure_review_labels') ||
               request.set_header('prophet.departure_review_labels', {})
      labels[value] ||= value.to_s.humanize
    end

    def departure_player_status(player)
      tag.span({ 'included' => 'Included', 'unknown_production' => 'Stats unavailable', 'skipped' => 'Skipped' }.fetch(player['status']))
    end

    def departure_absence_label(candidate)
      tag.span(candidate.values_at('team_name_source', 'team_name').compact.uniq.join(' · matched to '))
    end

    def departure_listing_status(batch)
      status = batch['acquisition_status']
      label = { 'completed' => 'Fetch finished · open review', 'queued' => 'Fetch queued', 'running' => 'Fetch in progress',
                'failed' => 'Fetch failed', 'incomplete' => 'Source needs attention' }.fetch(status, 'Prepared')
      tag.span(label, data: { acquisition_status: status })
    end
  end
end
