# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailyPredictionPerformance do
  let!(:fixture) { build_daily_forecast(probability:) }
  let(:probability) { 0.3 }
  let(:game) { fixture[0] }
  let(:prediction) { fixture[1] }
  let(:odds) { fixture[2] }
  let(:version) { fixture[3] }

  def row
    described_class.new(game.reload, ratings_config_version: version)
  end

  def issue(markets)
    BetRecommendationGenerator.call(game:)
    base = BetRecommendationIssue.last
    BetRecommendationIssue.create!(game:, prediction:, ratings_config_version: version, issued_at: Time.current,
                                   captured_start_time: game.start_time, odds_fetched_at: odds.fetched_at,
                                   evidence: base.evidence.merge('markets' => markets))
  end

  def pick(team, line = nil, price = -110)
    { 'team' => team, 'vegas_line' => line, 'vegas_odds' => price, 'confidence' => 0.6,
      'recommended' => true, 'ev' => 0.1, 'model_value' => 0.6 }
  end

  it 'grades saved away sides and total against corrected scores without changing evidence', :aggregate_failures do
    issue('spread' => pick('away', 5), 'moneyline' => pick('away', nil, 150), 'total' => pick('over', 140))
    expect(row.straight_up.status).to eq('pending')
    original = BetRecommendationIssue.order(:id).map(&:attributes)
    game.update!(status: :final, home_team_score: 70, away_team_score: 80)
    results = row.markets
    expect(row.straight_up.status).to eq('correct')
    expect(results.values.map(&:status)).to eq(%w[win win win])
    expect(results.fetch('moneyline').net_units).to eq(1.5)
    game.update!(home_team_score: 85, away_team_score: 80)
    expect(row.markets.values.map(&:status)).to eq(%w[push loss win])
    expect(BetRecommendationIssue.order(:id).map(&:attributes)).to eq(original)
  end

  it 'uses full precision stake-weighted arithmetic with pushes and deduplicates page rows', :aggregate_failures do
    issue('spread' => pick('home', 5), 'moneyline' => pick('home'), 'total' => pick('under', 140))
    game.update!(status: :final, home_team_score: 80, away_team_score: 70)
    summary = DailyPerformanceSummary.new([row, row])
    all = summary.betting.fetch('All bets')
    expect(all).to include(wins: 2, losses: 1, pushes: 0, settled: 3, stakes: 3)
    expect(all[:net_units]).to be_within(1e-10).of((200.0 / 110) - 1)
    expect(all[:roi]).to be_within(1e-10).of(((200.0 / 110) - 1) / 3)
    game.update!(home_team_score: 70, away_team_score: 70)
    expect(DailyPerformanceSummary.new([row]).betting.fetch('All bets')[:roi]).to be_nil
    game.update!(home_team_score: 80, away_team_score: 60)
    expect(row.markets.fetch('total')).to have_attributes(status: 'push', stake: 1, net_units: 0, realized_roi: 0)
  end

  it 'suppresses prior picks for latest no-play, absent markets and future quotes', :aggregate_failures do
    BetRecommendationGenerator.call(game:)
    issue('spread' => pick('home', 5).merge('recommended' => false), 'moneyline' => nil, 'total' => nil)
    game.update!(status: :final, home_team_score: 80, away_team_score: 70)
    expect(row.markets.values.map(&:status)).to eq(%w[no_play unavailable unavailable])
    expect(DailyPerformanceSummary.new([row]).betting.fetch('All bets')[:stakes]).to eq(0)
    game.update!(status: :scheduled, home_team_score: nil, away_team_score: nil)
    odds.update!(fetched_at: 1.day.from_now)
    BetRecommendationGenerator.call(game:)
    game.update!(status: :final, home_team_score: 70, away_team_score: 80)
    expect(row.markets.values.map(&:status)).to eq(%w[excluded excluded excluded])
    expect(DailyPerformanceSummary.new([row]).betting.fetch('All bets')[:stakes]).to eq(0)
  end

  context 'with exactly even model probability' do
    let(:probability) { 0.5 }

    it 'picks home at probability 0.5 independently of projected scores and moneyline side', :aggregate_failures do
      issue('moneyline' => pick('away', nil, 150))
      game.update!(status: :final, home_team_score: 80, away_team_score: 70)
      expect(row.straight_up).to have_attributes(status: 'correct', winner: game.home_team_name, probability: 0.5)
      expect(row.markets.fetch('moneyline').status).to eq('loss')
    end
  end

  it 'never mixes issues across forecast or model switches', :aggregate_failures do
    BetRecommendationGenerator.call(game:)
    original_issue = BetRecommendationIssue.last
    replacement = prediction.dup
    replacement.assign_attributes(generated_at: 30.minutes.ago, revision_key: 'daily-2')
    replacement.save!
    expect(row.prediction).to eq(replacement)
    expect(row.issue).to be_nil
    expect(row.recommendations).to be_empty
    BetRecommendationGenerator.call(game:)
    expect(row.issue.prediction_id).to eq(replacement.id)
    expect(original_issue.reload.prediction_id).to eq(prediction.id)
    other = create(:ratings_config_version)
    other_row = described_class.new(game.reload, ratings_config_version: other)
    expect(other_row.issue).to be_nil
    expect(other_row.markets.values.map(&:stake)).to eq([0, 0, 0])
  end

  it 'excludes an earlier corrected tipoff and never attributes replacement participant picks', :aggregate_failures do
    BetRecommendationGenerator.call(game:)
    game.update!(start_time: 2.hours.ago, status: :final, home_team_score: 70, away_team_score: 80)
    expect(row.straight_up.status).to eq('excluded')
    expect(row.markets.values.map(&:stake)).to eq([0, 0, 0])
    game.update!(start_time: 4.hours.from_now, status: :final_unmatched)
    replacement = create(:team_season, season: game.season)
    game.home_team_game.update!(team: replacement.team, team_season: replacement)
    expect(row.recommendations).to be_empty
    expect(row.markets.values.map(&:status)).to eq(%w[excluded excluded excluded])
  end

  it 'excludes invalid evidence, legacy, mismatched participants and unmatched outcomes', :aggregate_failures do
    issue('spread' => pick('home', nil), 'moneyline' => pick('home', nil, 99), 'total' => pick('under', 140))
    game.update!(status: :final, home_team_score: 80, away_team_score: 70)
    expect(row.markets.values.map(&:status)).to eq(%w[excluded excluded loss])
    game.update!(status: :final_unmatched)
    expect(row.straight_up.status).to eq('excluded')
    expect(row.markets.values.map(&:stake)).to eq([0, 0, 0])
    game.update!(status: :canceled)
    expect(row.markets.fetch('total').status).to eq('void')
    game.update!(status: :final)
    game.home_team_game.update!(team_season: create(:team_season, season: game.season))
    expect(row.straight_up.status).to eq('excluded')
    prediction.destroy!
    create(:prediction, game:, ratings_config_version: version,
                        home_team_snapshot: fixture[1].home_team_snapshot, away_team_snapshot: fixture[1].away_team_snapshot)
    expect(row.straight_up.status).to eq('excluded')
  end
end
