# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Importer::GamesImporter do
  let(:season) { Season.create!(year: 2025, start_date: '2024-11-01', end_date: '2025-04-10', name: '2024-25') }
  let(:home_team) { Team.create!(school: 'Home School', nickname: 'Home', slug: 'home', url: 'http://home.com') }
  let(:away_team) { Team.create!(school: 'Away School', nickname: 'Away', slug: 'away', url: 'http://away.com') }
  let(:home_team_season) { TeamSeason.create!(team: home_team, season:) }
  let(:away_team_season) { TeamSeason.create!(team: away_team, season:) }
  let(:home_alias) { TeamAlias.create!(team: home_team, value: home_team.school, source: 'sports_reference') }
  let(:away_alias) { TeamAlias.create!(team: away_team, value: away_team.school, source: 'sports_reference') }
  let(:date) { Date.new(2025, 1, 1) }

  let(:home_team_stats) do
    {
      minutes: 200,
      field_goals_made: 35,
      field_goals_attempted: 68,
      two_pt_made: 24,
      two_pt_attempted: 40,
      three_pt_made: 11,
      three_pt_attempted: 28,
      free_throws_made: 19,
      free_throws_attempted: 24,
      offensive_rebounds: 9,
      defensive_rebounds: 26,
      rebounds: 35,
      assists: 16,
      steals: 7,
      blocks: 4,
      turnovers: 11,
      fouls: 17,
      points: 100
    }
  end

  let(:away_team_stats) do
    {
      minutes: 200,
      field_goals_made: 31,
      field_goals_attempted: 65,
      two_pt_made: 21,
      two_pt_attempted: 39,
      three_pt_made: 10,
      three_pt_attempted: 26,
      free_throws_made: 18,
      free_throws_attempted: 22,
      offensive_rebounds: 10,
      defensive_rebounds: 24,
      rebounds: 34,
      assists: 14,
      steals: 6,
      blocks: 3,
      turnovers: 12,
      fouls: 19,
      points: 90
    }
  end

  let(:row) do
    {
      home_team: home_team.school,
      away_team: away_team.school,
      date:,
      home_team_score: 100,
      away_team_score: 90,
      url: 'http://example.com/game',
      home_team_stats: {},
      away_team_stats: {},
      season_id: season.id
    }
  end

  let(:completed_row) do
    row.merge(
      source_completed: true,
      source_completion_evidence: 'boxscore',
      source_updated_at: '2025-01-02T12:00:00Z',
      home_team_stats: home_team_stats,
      away_team_stats: away_team_stats
    )
  end

  before do
    home_team_season
    away_team_season
    home_alias
    away_alias
  end

  it 'creates a new game for unique teams and date' do
    expect do
      described_class.import([row])
    end.to change(Game, :count).by(1)
  end

  it 'assigns correct attributes to the new game' do
    described_class.import([row])
    game = Game.last
    expect(game.home_team_name).to eq home_team.school
    expect(game.away_team_name).to eq away_team.school
    expect(game.start_time.to_date).to eq date
  end

  it 'persists explicit venue fields from enriched game rows' do
    enriched_row = row.merge(
      date: Time.zone.local(2025, 1, 1, 18, 30),
      time_precision: 'instant',
      venue_type: 'neutral',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Little Caesars Arena',
      neutral: true
    )

    described_class.import([enriched_row])

    expect(Game.last).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Little Caesars Arena',
      start_time: Time.zone.local(2025, 1, 1, 18, 30),
      neutral: true
    )
  end

  it 'uses box score location as a lower-priority confirmed home venue fallback' do
    home_team.update!(home_venue: 'Home Arena')
    fallback_row = row.merge(box_score_location: 'Home Arena')

    described_class.import([fallback_row])

    expect(Game.last).to have_attributes(
      venue_type: 'home',
      venue_source: 'sports_reference_box_score_header',
      venue_confidence: 'confirmed',
      venue_name: 'Home Arena',
      neutral: false
    )
  end

  it 'does not use box score location fallback when enriched venue fields are present' do
    home_team.update!(home_venue: 'Home Arena')
    enriched_row = row.merge(
      box_score_location: 'Home Arena',
      venue_type: 'neutral',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Neutral Arena',
      neutral: true
    )

    described_class.import([enriched_row])

    expect(Game.last).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Neutral Arena',
      neutral: true
    )
  end

  ['Home Arena', 'Unrecognized Pavilion'].each do |header|
    it "preserves confirmed neutral schedule venue when finalizing with header #{header}" do
      home_team.update!(home_venue: 'Home Arena')
      initial = row.merge(venue_type: 'neutral', venue_source: 'sports_reference_team_schedule',
                          venue_confidence: 'confirmed', venue_name: 'Neutral Arena', neutral: true)
      described_class.import([initial])
      game = Game.last
      venue = game.attributes.slice('venue_type', 'venue_source', 'venue_confidence', 'venue_name', 'neutral')

      described_class.import([completed_row.merge(box_score_location: header)])

      expect(game.reload).to be_final
      expect(game.attributes.slice(*venue.keys)).to eq(venue)
    end
  end

  it 'still permits an explicit enriched venue update over stored source evidence' do
    initial = row.merge(venue_type: 'neutral', venue_source: 'sports_reference_team_schedule',
                        venue_confidence: 'confirmed', venue_name: 'Previous Arena', neutral: true)
    described_class.import([initial])
    game = Game.last
    enriched = completed_row.merge(venue_type: 'home', venue_source: 'sports_reference_team_schedule',
                                   venue_confidence: 'confirmed', venue_name: 'Reviewed Home Arena', neutral: false,
                                   box_score_location: 'Lower Priority Header')

    described_class.import([enriched])

    expect(game.reload).to have_attributes(status: 'final', venue_type: 'home', venue_source: 'sports_reference_team_schedule',
                                           venue_confidence: 'confirmed', venue_name: 'Reviewed Home Arena', neutral: false)
  end

  it 'preserves confirmed venue on an ordered repeated final without schedule enrichment' do
    home_team.update!(home_venue: 'Home Arena')
    initial = completed_row.merge(venue_type: 'neutral', venue_source: 'sports_reference_team_schedule',
                                  venue_confidence: 'confirmed', venue_name: 'Neutral Arena', neutral: true)
    described_class.import([initial])
    game = Game.last
    original = game.attributes
    accepted = GameObservation.where(game:, accepted: true).map(&:attributes)

    result = described_class.import([completed_row.merge(box_score_location: 'Home Arena', source_updated_at: '2025-01-03T12:00:00Z')])

    expect(result.first).to include(outcome: 'unchanged', accepted: false)
    expect(game.reload.attributes).to eq(original)
    expect(GameObservation.where(game:, accepted: true).map(&:attributes)).to eq(accepted)
  end

  it 'preserves manual venue fields when a complete game is re-imported' do
    described_class.import([row])
    game = Game.last
    game.update!(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )

    described_class.import([
                             completed_row.merge(
                               venue_type: 'home',
                               venue_source: 'sports_reference_team_schedule',
                               venue_confidence: 'confirmed',
                               venue_name: 'Home Arena',
                               neutral: false
                             )
                           ])

    expect(game.reload).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )
  end

  it 'preserves venue fields marked with the manual source during re-import' do
    described_class.import([row])
    game = Game.last
    game.update!(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'confirmed',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )

    described_class.import([
                             completed_row.merge(
                               venue_type: 'home',
                               venue_source: 'sports_reference_team_schedule',
                               venue_confidence: 'confirmed',
                               venue_name: 'Home Arena',
                               neutral: false
                             )
                           ])

    expect(game.reload).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'confirmed',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )
  end

  it 'preserves manual venue fields when an incomplete game is re-imported' do
    described_class.import([row])
    game = Game.last
    game.update!(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )

    described_class.import([
                             row.merge(
                               venue_type: 'home',
                               venue_source: 'sports_reference_team_schedule',
                               venue_confidence: 'confirmed',
                               venue_name: 'Home Arena',
                               neutral: false
                             )
                           ])

    expect(game.reload).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )
  end

  it 'does not create a duplicate game for the same teams and date' do
    described_class.import([row])
    expect do
      described_class.import([row])
    end.not_to change(Game, :count)
  end

  it 'does not match different scheduled games by shared daily schedule URL' do
    other_home_team = create(:team, school: 'Other Home', slug: 'other-home')
    other_away_team = create(:team, school: 'Other Away', slug: 'other-away')
    other_home_season = create(:team_season, team: other_home_team, season:)
    other_away_season = create(:team_season, team: other_away_team, season:)
    create(:team_alias, team: other_home_team, value: other_home_team.school, source: 'sports_reference')
    create(:team_alias, team: other_away_team, value: other_away_team.school, source: 'sports_reference')
    daily_schedule_url = 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025'
    other_row = row.merge(
      home_team: other_home_season.team.school,
      away_team: other_away_season.team.school
    )

    expect do
      described_class.import([row.merge(url: daily_schedule_url), other_row.merge(url: daily_schedule_url)])
    end.not_to change(Game, :count)
    expect(GameObservation.last(2).map(&:reason)).to eq(%w[missing_stable_game_identity missing_stable_game_identity])
  end

  it 'matches existing games by Eastern schedule date when enriched start time crosses UTC midnight' do
    existing_game = create(
      :game,
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1, 23, 0),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: 'http://example.com/old-game'
    )

    late_row = row.merge(
      date: ActiveSupport::TimeZone['Eastern Time (US & Canada)'].parse('2025-01-01 9:00pm'),
      time_precision: 'instant',
      url: 'http://example.com/enriched-game'
    )

    expect do
      described_class.import([late_row])
    end.not_to change(Game, :count)
    expect(existing_game.reload.url).to eq('http://example.com/enriched-game')
  end

  it 'matches existing games by box score URL when the stored date is a legacy UTC date' do
    box_score_url = '/cbb/boxscores/2025-01-01-00-home.html'
    existing_game = create(
      :game,
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: box_score_url
    )

    late_row = row.merge(
      date: ActiveSupport::TimeZone['Eastern Time (US & Canada)'].parse('2025-01-01 9:00pm'),
      time_precision: 'instant',
      url: box_score_url
    )

    expect do
      described_class.import([late_row])
    end.not_to change(Game, :count)
    expect(existing_game.reload.start_time).to eq(late_row[:date])
  end

  it 'matches existing neutral games by box score URL when stored teams are reversed' do
    box_score_url = '/cbb/boxscores/2025-01-01-00-neutral.html'
    existing_game = create(
      :game,
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: away_team.school,
      away_team_name: home_team.school,
      url: box_score_url,
      venue_type: 'neutral',
      neutral: true
    )
    create(:team_game, game: existing_game, team: away_team, team_season: away_team_season, home: true)
    create(:team_game, game: existing_game, team: home_team, team_season: home_team_season, home: false)

    neutral_row = row.merge(
      url: box_score_url,
      venue_type: 'neutral',
      venue_name: 'Neutral Arena',
      neutral: true
    )

    expect do
      described_class.import([neutral_row])
    end.not_to change(Game, :count)
    expect(GameObservation.last).to have_attributes(outcome: 'conflict', reason: 'participant_or_orientation_conflict')
    expect(existing_game.reload.home_team_game.team).to eq(away_team)
    expect(existing_game.away_team_game.team).to eq(home_team)
  end

  it 'matches legacy UTC-date games by teams and raw stored date' do
    existing_game = create(
      :game,
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: 'http://example.com/old-game'
    )

    late_row = row.merge(
      date: ActiveSupport::TimeZone['Eastern Time (US & Canada)'].parse('2025-01-01 9:00pm'),
      time_precision: 'instant',
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )

    expect do
      described_class.import([late_row])
    end.not_to change(Game, :count)
    expect(existing_game.reload.url).to eq('/cbb/boxscores/2025-01-01-00-home.html')
  end

  it 'keeps incomplete games scheduled' do
    described_class.import([row])
    expect(Game.last).to be_scheduled
  end

  it 'creates team game associations for incomplete scheduled games' do
    described_class.import([row])

    game = Game.last
    expect(game.home_team_game).to be_present
    expect(game.away_team_game).to be_present
    expect(game.home_team_game.team_season).to eq(home_team_season)
    expect(game.away_team_game.team_season).to eq(away_team_season)
  end

  it 'does not run venue enrichment during the standard import pipeline' do
    allow(Importer::GameVenueEnricher).to receive(:new).and_call_original

    described_class.import([row])

    expect(Importer::GameVenueEnricher).not_to have_received(:new)
  end

  it 'finalizes complete games' do
    described_class.import([completed_row])
    game = Game.last
    expect(game).to be_final
    expect(game.minutes).to be_present
  end

  it 'keeps a game scheduled when derived pace cannot be computed' do
    invalid_completed_row = completed_row.deep_dup
    invalid_completed_row[:home_team_stats][:minutes] = 0
    invalid_completed_row[:away_team_stats][:minutes] = 0

    expect { described_class.import([invalid_completed_row]) }.not_to raise_error

    expect(Game.last).to be_nil
    expect(GameObservation.last).to have_attributes(outcome: 'invalid')
  end

  it 'keeps new malformed complete boxes scheduled and logs the field reason' do
    malformed = completed_row.deep_dup
    malformed[:home_team_stats][:points] = 1
    allow(Rails.logger).to receive(:warn)

    described_class.import([malformed])

    expect(Game.last).to be_nil
    expect(TeamGame.count).to eq(0)
    expect(GameObservation.last).to have_attributes(outcome: 'invalid', reason: /home.*score/)
  end

  it 'preserves a final game and both boxes after an invalid complete correction inside an outer transaction' do
    described_class.import([completed_row])
    game = Game.last
    original_game = game.attributes
    original_sides = TeamGame.where(game:).order(:id).map(&:attributes)
    malformed = completed_row.deep_dup
    malformed[:home_team_score] = 1
    malformed[:home_team_stats][:points] = 1
    malformed[:away_team_stats][:assists] = 99

    Game.transaction { described_class.import([malformed]) }

    expect(game.reload.attributes).to eq(original_game)
    expect(TeamGame.where(game:).order(:id).map(&:attributes)).to eq(original_sides)
  end

  describe 'complete corrections with unresolved incoming sides' do
    let(:game) do
      described_class.import([completed_row])
      Game.last
    end
    let(:prediction) do
      version = create(:ratings_config_version)
      snapshots = [home_team_season, away_team_season].map do |team_season|
        create(:team_rating_snapshot, team_season:, ratings_config_version: version, snapshot_date: date - 1.day)
      end
      create(:prediction, game:, ratings_config_version: version,
                          home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                          home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                          home_defensive_efficiency: 100, away_defensive_efficiency: 110, pace: 70)
    end

    before do
      prediction
      game.finalize
    end

    %i[unknown_team missing_team_season].each do |resolution_failure|
      it "preserves the final game, boxes and prediction errors for #{resolution_failure}" do
        incoming_name = 'Unresolved Away'
        if resolution_failure == :missing_team_season
          incoming_team = create(:team, school: incoming_name, slug: 'unresolved-away')
          create(:team_alias, team: incoming_team, value: incoming_name, source: 'sports_reference')
        end
        original_game = game.attributes
        original_sides = TeamGame.where(game:).order(:id).map(&:attributes)
        original_prediction = prediction.reload.attributes
        correction = completed_row.deep_dup
        correction[:source_updated_at] = '2025-01-03T12:00:00Z'
        correction[:home_team_score] = correction[:home_team_stats][:points] = 101
        correction[:home_team_stats][:free_throws_made] = 20
        correction[:away_team] = incoming_name
        correction[:source_completed] = true
        correction[:away_team_stats][:rebounds] = 35

        Game.transaction { described_class.import([correction]) }

        expect(game.reload.attributes).to eq(original_game)
        expect(TeamGame.where(game:).order(:id).map(&:attributes)).to eq(original_sides)
        expect(prediction.reload.attributes).to eq(original_prediction)
      end
    end
  end

  it 'applies valid complete corrections when both incoming team seasons resolve' do
    described_class.import([completed_row])
    game = Game.last
    correction = completed_row.deep_dup
    correction[:source_updated_at] = '2025-01-03T12:00:00Z'
    correction[:home_team_score] = correction[:home_team_stats][:points] = 101
    correction[:home_team_stats][:free_throws_made] = 20

    described_class.import([correction])

    expect(game.reload).to have_attributes(status: 'final', home_team_score: 101)
    expect(game.home_team_game).to have_attributes(points: 101, free_throws_made: 20)
  end

  it 'leaves a complete row with an unmatched side scheduled instead of averaging only one team' do
    unknown = completed_row.merge(away_team: 'Unknown Team')
    described_class.import([unknown])
    expect(Game.last).to be_nil
    expect(GameObservation.last).to have_attributes(outcome: 'unmatched')
  end

  it 'does not resave rolled-back derived fields when normalized minutes are invalid' do
    malformed = completed_row.deep_dup
    malformed[:home_team_stats][:minutes] = 4
    malformed[:away_team_stats][:minutes] = 4

    described_class.import([malformed])

    expect(Game.last).to be_nil
    expect(GameObservation.last).to have_attributes(outcome: 'invalid')
  end

  it 'does not downgrade an existing final game when an incomplete row is imported later' do
    described_class.import([completed_row])
    game = Game.last

    described_class.import([row.merge(home_team_score: nil, away_team_score: nil)])

    expect(game.reload).to be_final
    expect(game.home_team_score).to eq(100)
    expect(game.away_team_score).to eq(90)
  end

  it 'holds incomplete refreshes even for broken legacy finals' do
    described_class.import([completed_row])
    game = Game.last
    game.update!(minutes: nil, possessions: nil) # simulate bad historical finalization

    described_class.import([row.merge(home_team_score: nil, away_team_score: nil)])

    expect(game.reload).to be_final
    expect(GameObservation.last).to have_attributes(outcome: 'conflict')
  end

  it 'creates a second game for a true double header (same teams, same day, different time)' do
    skip('double header logic not implemented yet')
    # This is currently not supported due to strict uniqueness validation by teams and date.
    # If double header support is needed, update the model validation and remove this skip.
    row2 = row.merge(date: date.to_datetime.change({ hour: 20 }))
    described_class.import([row])
    expect do
      described_class.import([row2])
    end.to change(Game, :count).by(1)
  end

  describe 'source-confirmed unmatched results' do
    let(:unmatched_row) { completed_row.merge(away_team: 'Unknown School') }

    it 'retains unresolved raw evidence without creating partial domain records' do
      expect { described_class.import([unmatched_row]) }.not_to change(Game, :count)
      expect(TeamGame.count).to eq(0)
      expect(Team.count).to eq(2)
      expect(GameObservation.last.normalized_payload.dig('home', 'stats', 'points')).to eq(100)
      expect(GameObservation.last).to have_attributes(outcome: 'unmatched', accepted: false)
    end

    it 'preserves the completed enum meanings for existing legacy results' do
      expect(Game.statuses).to include('scheduled' => 0, 'final' => 1, 'canceled' => 2, 'final_unmatched' => 3)
      game = create(:game, season:, status: :final_unmatched)
      expect(Game.completed).to include(game)
      expect(Game.final).not_to include(game)
    end

    [nil, false, 'true', 1].each do |confirmation|
      it "keeps unresolved observations audit-only with confirmation #{confirmation.inspect}" do
        expect { described_class.import([unmatched_row.merge(source_completed: confirmation)]) }.not_to change(Game, :count)
        expect(GameObservation.last.accepted).to be(false)
      end
    end

    [nil, -1, 1.5, '1.5', 'bad', '100', true].each do |score|
      it "never synthesizes an unresolved result for score #{score.inspect}" do
        expect { described_class.import([unmatched_row.merge(away_team_score: score)]) }.not_to change(Game, :count)
        expect(GameObservation.last.accepted).to be(false)
      end
    end

    it 'requires distinct present participants' do
      ['', home_team.school].each do |name|
        expect { described_class.import([unmatched_row.merge(away_team: name)]) }.not_to change(Game, :count)
        expect(GameObservation.last).to have_attributes(accepted: false)
      end
    end

    it 'keeps digit-string raw scores available in retained evidence' do
      described_class.import([unmatched_row.merge(home_team_score: '100', away_team_score: '90')])
      expect(GameObservation.last.normalized_payload.dig('home', 'score')).to eq(100)
      expect(Game.count).to eq(0)
    end

    it 'cannot bypass ordinary matched box validation' do
      described_class.import([completed_row.merge(home_team_stats: home_team_stats.merge(points: 1))])
      expect(Game.count).to eq(0)
      expect(GameObservation.last).to have_attributes(outcome: 'invalid')
    end

    describe 'promotion' do
      let(:game) do
        record = create(:game, season:, start_time: Game.schedule_time_for(date), url: row[:url],
                               home_team_name: home_team.school, away_team_name: away_team.school,
                               home_team_score: 100, away_team_score: 90, status: :final_unmatched)
        create(:team_game, game: record, team: home_team, team_season: home_team_season, home: true, points: 100)
        record
      end
      let(:prediction) do
        version = create(:ratings_config_version)
        snapshots = [home_team_season, away_team_season].map do |team_season|
          create(:team_rating_snapshot, team_season:, ratings_config_version: version, snapshot_date: date - 1.day)
        end
        create(:prediction, game:, ratings_config_version: version,
                            home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                            home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                            home_defensive_efficiency: 100, away_defensive_efficiency: 110, pace: 70)
      end

      it 'promotes the same game and computes prediction residuals from validated actuals' do
        prediction
        id = game.id
        described_class.import([completed_row])
        expect(game.reload).to be_final
        expect(game.id).to eq(id)
        # Home possessions: 68-9+11+0.475*24 = 81.4; away rounds to 77.5; mean stores as 79.5.
        expected = 110 - (100 / 81.4 * 100).round(3)
        expect(prediction.reload.home_offensive_efficiency_error.to_f).to be_within(0.001).of(expected)
        expect(prediction.pace_error.to_f).to be_within(0.001).of(-9.5)
      end

      it 'restores the entire unmatched result after invalid or missing-derived promotion' do
        prediction
        original = game.attributes
        sides = TeamGame.where(game:).map(&:attributes)
        errors = prediction.attributes
        [completed_row.merge(home_team_stats: home_team_stats.merge(points: 1)),
         completed_row.merge(home_team_stats: home_team_stats.merge(minutes: 0))].each do |incoming|
          Game.transaction { described_class.import([incoming]) }
          expect(game.reload.attributes).to eq(original)
          expect(TeamGame.where(game:).map(&:attributes)).to eq(sides)
          expect(prediction.reload.attributes).to eq(errors)
        end
      end

      it 'restores unmatched state when derived pace is unavailable after valid box validation' do
        prediction
        original = game.attributes
        sides = TeamGame.where(game:).map(&:attributes)
        errors = prediction.attributes
        allow(ProphetRatings::GameFinalizer).to receive(:new).and_wrap_original do |method, record, **options|
          allow(record).to receive(:pace).and_return(nil)
          method.call(record, **options)
        end
        described_class.import([completed_row])
        expect(game.reload.attributes).to eq(original)
        expect(TeamGame.where(game:).map(&:attributes)).to eq(sides)
        expect(prediction.reload.attributes).to eq(errors)
      end

      it 'propagates persistence failures and rolls back promotion including boxes and errors' do
        prediction
        original = game.attributes
        sides = TeamGame.where(game:).map(&:attributes)
        errors = prediction.attributes
        allow(ProphetRatings::GameFinalizer).to receive(:prediction_error_attributes).and_wrap_original do |method, record|
          record.readonly!
          method.call(record)
        end
        expect { described_class.import([completed_row]) }.to raise_error(ActiveRecord::ReadOnlyRecord)
        expect(game.reload.attributes).to eq(original)
        expect(TeamGame.where(game:).map(&:attributes)).to eq(sides)
        expect(prediction.reload.attributes).to eq(errors)
      end
    end
  end
end
