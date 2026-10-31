# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateBetRecommendationsJob do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  let(:season) { create(:season) }
  let(:version) { create(:ratings_config_version, current: true) }
  let(:game) { create(:game, season:, status: :scheduled, start_time: 1.hour.from_now) }

  before { travel_to(Time.utc(2026, 2, 1, 15)) }

  it 'generates recommendations for upcoming games and refreshes existing rows without duplicating them' do
    prediction = create_game_prediction(game)
    odds = create_odds(game)
    tomorrow = create(:game, season:, status: :scheduled, start_time: 1.day.from_now)
    create_game_prediction(tomorrow)
    create_odds(tomorrow)

    expect { described_class.perform_now }.to change(BetRecommendation, :count).by(6)
    expect(game.bet_recommendations).to all(have_attributes(prediction:, game_odd: odds, current: true))
    expect(game.bet_recommendations.pluck(:bet_type)).to contain_exactly('spread', 'moneyline', 'total')

    odds.update!(spread_point: -7.5)
    expect { described_class.perform_now }.not_to change(BetRecommendation, :count)
    expect(game.bet_recommendations.find_by!(bet_type: 'spread').vegas_line.abs).to eq(7.5)
  end

  it 'skips started, final, canceled, and incomplete games while processing a later eligible game' do
    [[:scheduled, 1.second.ago], [:scheduled, Time.current], [:final, 1.hour.from_now],
     [:final_unmatched, 2.hours.from_now], [:canceled, 3.hours.from_now]].each do |status, start_time|
      excluded = create(:game, season:, status:, start_time:, home_team_name: "Home #{status} #{start_time.to_i}")
      create_game_prediction(excluded)
      create_odds(excluded)
    end
    missing_prediction = create(:game, season:, status: :scheduled, start_time: 2.days.from_now)
    create_odds(missing_prediction)
    missing_odds = create(:game, season:, status: :scheduled, start_time: 3.days.from_now)
    create_game_prediction(missing_odds)
    eligible = create(:game, season:, status: :scheduled, start_time: 4.days.from_now)
    create_game_prediction(eligible)
    create_odds(eligible)

    described_class.perform_now

    expect(BetRecommendation.distinct.pluck(:game_id)).to eq([eligible.id])
  end

  it 'rolls back a failed game, processes later games, and queues a retry' do
    create_game_prediction(game)
    odds = create_odds(game)
    described_class.perform_now
    original = game.bet_recommendations.order(:id).map(&:attributes)
    odds.update!(spread_point: -7.5)
    later = create(:game, season:, status: :scheduled, start_time: 1.day.from_now)
    create_game_prediction(later)
    create_odds(later)
    allow(BetRecommendationGenerator).to receive(:call).and_wrap_original do |generate, **arguments|
      result = generate.call(**arguments)
      raise 'Synthetic failure after recommendation writes' if arguments[:game].id == game.id

      result
    end

    expect { described_class.perform_now }.to have_enqueued_job(described_class)

    expect(game.bet_recommendations.order(:id).map(&:attributes)).to eq(original)
    expect(later.bet_recommendations.pluck(:bet_type)).to contain_exactly('spread', 'moneyline', 'total')
  end

  it 'retires unavailable markets and restores them without duplicate rows when odds return' do
    create_game_prediction(game)
    odds = create_odds(game)
    described_class.perform_now
    identifiers = game.bet_recommendations.order(:id).pluck(:id)
    odds.update!(spread_point: nil, total_points: nil, moneyline_home: nil, moneyline_away: nil)

    described_class.perform_now

    expect(game.current_bet_recommendations).to be_empty
    expect(game.bet_recommendations.order(:id).pluck(:id)).to eq(identifiers)
    odds.update!(spread_point: -4.5, total_points: 145.5, moneyline_home: -120, moneyline_away: 100)
    described_class.perform_now
    expect(game.current_bet_recommendations.order(:id).pluck(:id)).to eq(identifiers)
  end

  it 'retires old-model picks when the new default has no prediction' do
    create_game_prediction(game)
    create_odds(game)
    described_class.perform_now
    previous = game.bet_recommendations.order(:id).pluck(:id, :prediction_id, :ev)
    create(:ratings_config_version).activate

    described_class.perform_now

    expect(game.current_prediction).to be_nil
    expect(game.current_bet_recommendations).to be_empty
    expect(game.bet_recommendations.order(:id).pluck(:id, :prediction_id, :ev)).to eq(previous)
  end

  it 'compares only available moneyline sides and preserves spread and total output' do
    create_game_prediction(game)
    odds = create_odds(game)
    [[-1000, nil, 'home', -1000, -0.34], [nil, -1000, 'away', -1000, -0.56]].each do |home, away, side, price, ev|
      odds.update!(moneyline_home: home, moneyline_away: away)

      expect { described_class.perform_now }.not_to have_enqueued_job(described_class)

      expect(game.current_bet_recommendations.pluck(:bet_type)).to contain_exactly('spread', 'moneyline', 'total')
      expect(game.current_bet_recommendations.find_by!(bet_type: 'moneyline')).to have_attributes(
        team: side, vegas_odds: price, ev:, recommended: false
      )
    end
  end

  it 'retires unpriced spread and total selections instead of assuming a price' do
    create_game_prediction(game)
    odds = create_odds(game)
    described_class.perform_now
    [nil, 0].each do |price|
      # Home is favored to cover -4.5; the model total 145 favors under 145.5.
      odds.update!(spread_home_odds: price, total_under_odds: price)
      described_class.perform_now
      expect(game.current_bet_recommendations.pluck(:bet_type)).to eq(['moneyline'])
    end
  end

  def create_game_prediction(target)
    home, away = Array.new(2) { create(:team_season, season:) }
    create(:team_game, game: target, team: home.team, team_season: home, opponent_team_season: away, home: true)
    create(:team_game, game: target, team: away.team, team_season: away, opponent_team_season: home, home: false)
    snapshots = [home, away].map do |team_season|
      create(:team_rating_snapshot, team_season:, team: team_season.team, season:, ratings_config_version: version,
                                    snapshot_date: target.schedule_date - 1.day)
    end
    create(:prediction, game: target, home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                        ratings_config_version: version, home_score: 75, away_score: 70, pace: 70,
                        home_offensive_efficiency: 107.143, away_offensive_efficiency: 100, home_win_probability: 0.6)
  end

  def create_odds(target)
    create(:game_odd, game: target, fetched_at: Time.current, spread_point: -4.5,
                      spread_home_odds: -110, spread_away_odds: -110, moneyline_home: -120, moneyline_away: 100,
                      total_points: 145.5, total_over_odds: -110, total_under_odds: -110)
  end
end
