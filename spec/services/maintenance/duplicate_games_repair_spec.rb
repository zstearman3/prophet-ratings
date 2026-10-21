# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maintenance::DuplicateGamesRepair do
  let(:season) { create(:season, year: 2025, start_date: '2024-11-01', end_date: '2025-04-10') }
  let(:home_team) { create(:team, school: 'Home School') }
  let(:away_team) { create(:team, school: 'Away School') }
  let(:home_team_season) { create(:team_season, team: home_team, season:) }
  let(:away_team_season) { create(:team_season, team: away_team, season:) }
  let(:output) { StringIO.new }

  def create_game(attrs)
    build(:game, attrs).tap { |game| game.save!(validate: false) }
  end

  def create_bookmaker_odd_for(game)
    create(
      :bookmaker_odd,
      game:,
      bookmaker: 'DraftKings',
      fetched_at: Time.current,
      market: 'h2h',
      team_name: home_team.school
    )
  end

  it 'reports duplicate groups without mutating records by default' do
    create_game(
      season:,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )

    result = described_class.new(output:).call

    expect(result.applied).to be(false)
    expect(result.groups.size).to eq(1)
    expect(result.deleted_game_ids).to be_empty
    expect(Game.count).to eq(2)
    expect(output.string).to include('DRY RUN')
  end

  it 'applies repairs by keeping the strongest survivor and deleting duplicates' do
    scheduled_duplicate = create_game(
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    final_survivor = create_game(
      season:,
      status: :final,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html',
      venue_type: 'home',
      venue_confidence: 'confirmed',
      venue_name: 'Home Arena'
    )
    create(:team_game, game: final_survivor, team: home_team, team_season: home_team_season, home: true)
    create(:team_game, game: final_survivor, team: away_team, team_season: away_team_season, home: false)

    result = described_class.new(apply: true, output:).call

    expect(result.applied).to be(true)
    expect(result.deleted_game_ids).to contain_exactly(scheduled_duplicate.id)
    expect(Game.exists?(scheduled_duplicate.id)).to be(false)
    expect(Game.exists?(final_survivor.id)).to be(true)
  end

  it 'reassigns safe dependent records before deleting a duplicate' do
    survivor = create_game(
      season:,
      status: :final,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    duplicate = create_game(
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    game_odd = create(:game_odd, game: duplicate, fetched_at: Time.current)
    bookmaker_odd = create(:bookmaker_odd, game: duplicate, bookmaker: 'DraftKings', fetched_at: Time.current, market: 'h2h')
    create(:team_game, game: duplicate, team: home_team, team_season: home_team_season, home: true)
    create(:team_game, game: duplicate, team: away_team, team_season: away_team_season, home: false)

    described_class.new(apply: true, output:).call

    expect(game_odd.reload.game).to eq(survivor)
    expect(bookmaker_odd.reload.game).to eq(survivor)
    expect(survivor.reload.home_team_game.team).to eq(home_team)
    expect(survivor.away_team_game.team).to eq(away_team)
    expect(Game.exists?(duplicate.id)).to be(false)
  end

  it 'deletes duplicate bookmaker odds when the survivor already has the same sportsbook market' do
    survivor = create_game(
      season:,
      status: :final,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    duplicate = create_game(
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    survivor_odd = create_bookmaker_odd_for(survivor)
    duplicate_odd = create_bookmaker_odd_for(duplicate)

    result = described_class.new(apply: true, output:).call

    expect(BookmakerOdd.exists?(duplicate_odd.id)).to be(false)
    expect(survivor_odd.reload.game).to eq(survivor)
    expect(result.reassigned_counts[:bookmaker_odds_deleted]).to eq(1)
  end

  it 'detects reversed neutral duplicates by unordered team pair and schedule date' do
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025',
      venue_type: 'neutral',
      neutral: true
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:30pm'),
      home_team_name: away_team.school,
      away_team_name: home_team.school,
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025',
      venue_type: 'neutral',
      neutral: true
    )

    result = described_class.new(output:).call

    expect(result.groups.size).to eq(1)
    expect(result.groups.first.games.map(&:id).size).to eq(2)
  end

  it 'does not group unrelated games by shared daily schedule URL' do
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 7:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025'
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: 'Other Home',
      away_team_name: 'Other Away',
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025'
    )

    result = described_class.new(output:).call

    expect(result.groups).to be_empty
  end

  it 'hard-orders unmatched results before populated schedules without importing their stale boxes' do
    attrs = { season:, start_time: Game.schedule_time_for(Date.new(2025, 1, 1)),
              home_team_name: home_team.school, away_team_name: away_team.school, url: '/same.html' }
    scheduled = create_game(attrs.merge(status: :scheduled, possessions: 80, minutes: 40))
    create(:team_game, game: scheduled, team: home_team, team_season: home_team_season, home: true, offensive_rating: 999)
    create(:team_game, game: scheduled, team: away_team, team_season: away_team_season, home: false, offensive_rating: 999)
    create_bookmaker_odd_for(scheduled)
    create(:game_odd, game: scheduled, fetched_at: Time.current)
    version = create(:ratings_config_version)
    snapshots = [home_team_season, away_team_season].map do |team_season|
      create(:team_rating_snapshot, team_season:, ratings_config_version: version)
    end
    create(:prediction, game: scheduled, ratings_config_version: version,
                        home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last)
    unmatched = create_game(attrs.merge(status: :final_unmatched, home_team_score: 70, away_team_score: 60))
    side = create(:team_game, game: unmatched, team: home_team, team_season: home_team_season, home: true, assists: 4)

    report = described_class.new(output:).call
    expect(report.groups.first.survivor).to eq(unmatched)
    expect(Game.exists?(scheduled.id)).to be(true)
    described_class.new(apply: true, output:).call
    expect(unmatched.reload).to have_attributes(status: 'final_unmatched', home_team_score: 70,
                                                away_team_score: 60, possessions: nil, minutes: nil)
    expect(unmatched).to have_attributes(home_team_game: side, away_team_game: nil)
    expect(side.reload).to have_attributes(assists: 4, offensive_rating: nil)
  end

  it 'prioritizes strict finals over unmatched completed duplicates' do
    attrs = { season:, start_time: Game.schedule_time_for(Date.new(2025, 1, 1)),
              home_team_name: home_team.school, away_team_name: away_team.school, url: '/same.html' }
    create_game(attrs.merge(status: :final_unmatched))
    final = create_game(attrs.merge(status: :final))
    expect(described_class.new(output:).call.groups.first.survivor).to eq(final)
  end

  describe 'external identity safeguards' do
    def duplicate_pair(day)
      attrs = { season:, start_time: Game.schedule_time_for(Date.new(2025, 1, day)),
                home_team_name: home_team.school, away_team_name: away_team.school, url: "/duplicate-#{day}.html" }
      [create_game(attrs.merge(status: :final)), create_game(attrs.merge(status: :scheduled))]
    end

    def stored_repair_records
      [Game, TeamGame, Prediction, GameOdd, BookmakerOdd, BetRecommendation, GameExternalIdentity, GameObservation].index_with do |model|
        model.order(:id).map(&:attributes)
      end
    end

    def capture_writes(&)
      writes = []
      subscriber = lambda do |*args|
        sql = args.last[:sql]
        writes << sql if sql.match?(/\A\s*(?:INSERT|UPDATE|DELETE)\b/i)
      end
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
      writes
    end

    %w[scheduled unmatched invalid].each do |outcome|
      it "preflights observation-bearing later duplicates (#{outcome}) before any SQL writes" do
        _survivor, safe_duplicate = duplicate_pair(1)
        _protected_survivor, duplicate = duplicate_pair(2)
        create(:game_odd, game: safe_duplicate, fetched_at: Time.current)
        GameObservation.create!(game: duplicate, outcome:, accepted: outcome == 'scheduled')
        before_records = stored_repair_records
        writes = capture_writes do
          expect { described_class.new(apply: true, output:).call }
            .to raise_error(ArgumentError, /#{duplicate.id}.*review observation history/)
        end
        expect(writes).to be_empty
        expect(stored_repair_records).to eq(before_records)
      end
    end

    it 'reports protected observations on dry runs and permits survivor-only evidence' do
      survivor, duplicate = duplicate_pair(1)
      record = GameObservation.create!(game: duplicate, outcome: 'unmatched')
      before_records = stored_repair_records
      expect(capture_writes { described_class.new(output:).call }).to be_empty
      expect(stored_repair_records).to eq(before_records)
      record.delete # Synthetic fixture only; repair must never move immutable history.
      record = GameObservation.create!(game: survivor, outcome: 'scheduled', accepted: true)
      original = record.attributes
      expect(described_class.new(apply: true, output:).call.deleted_game_ids).to eq([duplicate.id])
      expect(record.reload.attributes).to eq(original)
    end

    it 'prioritizes identity guidance over observation protection' do
      _survivor, duplicate = duplicate_pair(1)
      GameObservation.create!(game: duplicate, outcome: 'invalid')
      GameExternalIdentity.associate!(game: duplicate, provider: 'synthetic', external_id: 'protected')
      expect { described_class.new(apply: true, output:).call }
        .to raise_error(ArgumentError, /review identity mappings/)
    end

    it 'rechecks late observation evidence under locks before moving dependents' do
      _survivor, duplicate = duplicate_pair(1)
      create(:game_odd, game: duplicate, fetched_at: Time.current)
      before_records = stored_repair_records
      repair = described_class.new(apply: true, output:)
      allow(repair).to receive(:validate_frozen_forecasts!).and_wrap_original do |method, group|
        method.call(group)
        GameObservation.create!(game: duplicate, outcome: 'unmatched')
      end
      expect { repair.call }.to raise_error(ArgumentError, /review observation history/)
      expect(stored_repair_records).to eq(before_records)
    end

    it 'rejects all groups before any merge or dependent write when later deletion candidates have identities' do
      _safe_survivor, safe_duplicate = duplicate_pair(1)
      _active_survivor, active_duplicate = duplicate_pair(2)
      _retired_survivor, retired_duplicate = duplicate_pair(3)
      create(:team_game, game: safe_duplicate, team: home_team, team_season: home_team_season, home: true)
      [safe_duplicate, active_duplicate, retired_duplicate].each do |game|
        create(:game_odd, game:, fetched_at: Time.current)
      end
      GameExternalIdentity.associate!(game: active_duplicate, provider: 'provider_a', external_id: 'active')
      GameExternalIdentity.create!(game: retired_duplicate, provider: 'provider_a', external_id: 'retired', superseded_at: 1.day.ago)
      before_records = stored_repair_records
      repair = described_class.new(scope: Game.order(:id), apply: true, output:)
      allow(repair).to receive(:merge_duplicate!).and_call_original
      blocked_ids = [active_duplicate.id, retired_duplicate.id].sort.join(', ')

      writes = capture_writes do
        expect { repair.call }.to raise_error(ArgumentError, /#{blocked_ids}.*review identity mappings/)
      end

      expect(repair).not_to have_received(:merge_duplicate!)
      expect(writes).to be_empty
      expect(stored_repair_records).to eq(before_records)
    end

    it 'keeps dry runs read-only and reports an identity-bearing deletion candidate' do
      _survivor, duplicate = duplicate_pair(1)
      GameExternalIdentity.associate!(game: duplicate, provider: 'provider_a', external_id: 'active')
      before_records = stored_repair_records
      result = nil

      writes = capture_writes { result = described_class.new(output:).call }

      expect(result.groups.first.duplicates).to eq([duplicate])
      expect(result.deleted_game_ids).to be_empty
      expect(output.string).to include('DRY RUN', "duplicates=#{duplicate.id}")
      expect(writes).to be_empty
      expect(stored_repair_records).to eq(before_records)
    end

    it 'allows a survivor-only identity and preserves it while merging safe dependents' do
      survivor, duplicate = duplicate_pair(1)
      identity = GameExternalIdentity.associate!(game: survivor, provider: 'provider_a', external_id: 'survivor')
      original_identity = identity.attributes
      odd = create(:game_odd, game: duplicate, fetched_at: Time.current)

      result = described_class.new(apply: true, output:).call

      expect(result.deleted_game_ids).to eq([duplicate.id])
      expect(odd.reload.game).to eq(survivor)
      expect(identity.reload.attributes).to eq(original_identity)
      expect(GameExternalIdentity.count).to eq(1)
    end

    it 'rechecks deletion candidates after group locks before moving any dependents' do
      _survivor, duplicate = duplicate_pair(1)
      create(:game_odd, game: duplicate, fetched_at: Time.current)
      before_records = stored_repair_records
      repair = described_class.new(apply: true, output:)
      allow(repair).to receive(:merge_duplicate!).and_call_original
      allow(repair).to receive(:validate_frozen_forecasts!).and_wrap_original do |method, group|
        method.call(group)
        GameExternalIdentity.associate!(game: duplicate, provider: 'provider_a', external_id: 'late')
      end

      expect { repair.call }.to raise_error(ArgumentError, /#{duplicate.id}.*review identity mappings/)
      expect(repair).not_to have_received(:merge_duplicate!)
      expect(stored_repair_records).to eq(before_records)
    end
  end
end
