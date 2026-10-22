# frozen_string_literal: true

module DepartureWorkflow
  def departure_fields
    { 'draft_year' => '2025', 'prior_season_year' => '2025', 'target_year' => '2026', 'expected_picks' => (1..60).to_a.join(' '),
      'sources' => { '0' => { 'type' => 'nba_results', 'url' => 'https://www.nba.com/news/2025-nba-draft-order' },
                     '1' => { 'type' => 'sidearm_totals', 'url' => 'https://school.example/stats/2024-25',
                              'team_name_source' => 'Sample School', 'scope_evidence' => 'Verified final overall scope' } } }
  end

  def capture_departures(batch)
    allow(HTTParty).to receive(:get) do |url, **|
      double(body: Rails.root.join('spec/fixtures/departures', url.include?('nba.com') ? 'draft.html' : 'school.html').read, code: 200)
    end
    attempt = Departures::BatchPreparation.new(batch).acquire
    AcquireDepartureBatchJob.perform_now(attempt.id)
    attempt.reload
  end

  def departure_rows(team)
    rows = (1..60).to_h do |pick|
      ["2025/#{pick}", { 'status' => 'verified_no_college', 'reason' => 'Reviewed synthetic participation evidence',
                         'evidence_source_ids' => ['source-1'] }]
    end
    { 1 => 'alpha/101', 60 => 'beta/102' }.each do |pick, player|
      rows["2025/#{pick}"] = { 'status' => 'eligible_prior_season', 'reason' => 'Reviewed synthetic identity',
                               'evidence_source_ids' => %w[source-1 source-2],
                               'stints' => { '0' => { 'production_key' => "source-2|https://school.example/sports/mens-basketball/roster/#{player}",
                                                      'team_id' => team.id.to_s,
                                                      'identity_evidence_source_ids' => %w[source-1 source-2] } } }
    end
    rows
  end

  def save_departure_rows(batch, rows)
    review = Departures::BatchReview.new(batch)
    review.save('review_key' => review.review_key, 'rows' => rows)
    review
  end

  def approve_departures(batch, extra = {})
    review = Departures::BatchReview.new(batch)
    review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }.merge(extra), reviewer: 'admin@example.com')
  end
end

RSpec.configure { |config| config.include DepartureWorkflow }
