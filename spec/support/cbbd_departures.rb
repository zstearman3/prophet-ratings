# frozen_string_literal: true

module CbbdDepartures
  def cbbd_fields
    { 'draft_year' => '2025', 'prior_season_year' => '2025', 'target_year' => '2026', 'expected_picks' => (1..60).to_a.join(' '),
      'scope_evidence' => 'Reviewed synthetic final regular and postseason', 'max_requests' => '15', 'retries' => '2' }
  end

  def stub_cbbd
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('synthetic-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |uri, _key|
      scope = URI.decode_www_form(uri.query).to_h['seasonType']
      payload = case uri.path
                when '/draft/picks' then cbbd_picks
                when '/stats/player/season' then cbbd_players(scope)
                when '/stats/team/season' then cbbd_teams(scope)
                end
      { status: 200, body: JSON.generate(payload), headers: {} }
    end
  end

  def cbbd_picks
    (1..60).map do |pick|
      { 'year' => 2025, 'overall' => pick, 'round' => pick <= 30 ? 1 : 2, 'pick' => pick <= 30 ? pick : pick - 30,
        'name' => "Synthetic #{pick}", 'athleteId' => pick, 'sourceTeamCollegeId' => 20, 'sourceTeamLocation' => 'Sample School' }
    end
  end

  def cbbd_players(scope)
    (1..61).map do |id|
      points = { 1 => scope == 'regular' ? 400 : 100, 61 => scope == 'regular' ? 1200 : 300 }.fetch(id, 0)
      { 'season' => 2025, 'athleteId' => id, 'athleteSourceId' => "external-#{id}", 'name' => "Synthetic #{id}",
        'teamId' => 20, 'team' => 'Sample School', 'points' => points, 'games' => scope == 'regular' ? 30 : 2, 'minutes' => 20.5 }
    end
  end

  def cbbd_teams(scope)
    [{ 'season' => 2025, 'teamId' => 20, 'team' => 'Sample School', 'games' => scope == 'regular' ? 30 : 2,
       'totalMinutes' => scope == 'regular' ? 1200 : 80, 'teamStats' => { 'points' => { 'total' => scope == 'regular' ? 1600 : 400 } } }]
  end

  def cbbd_rows(team)
    (1..60).to_h do |pick|
      ["2025/#{pick}", { 'status' => 'eligible_prior_season', 'reason' => 'Reviewed exact typed identity',
                         'evidence_source_ids' => %w[draft player-regular player-postseason team-regular team-postseason],
                         'stints' => { '0' => { 'production_key' => "cbbd/team/20|cbbd/athlete/#{pick}", 'team_id' => team.id.to_s,
                                                'identity_evidence_source_ids' => %w[draft player-regular player-postseason] } } }]
    end
  end

  def capture_cbbd(batch)
    stub_cbbd
    attempt = Departures::BatchPreparation.new(batch).acquire
    AcquireDepartureBatchJob.perform_now(attempt.id)
    attempt.reload
  end
end

RSpec.configure { |config| config.include CbbdDepartures }
