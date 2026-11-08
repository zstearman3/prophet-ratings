# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BetSettlementRecorder do
  let!(:fixture) { build_daily_forecast }
  let(:game) { fixture[0] }
  let(:prediction) { fixture[1] }
  let(:odds) { fixture[2] }
  let(:version) { fixture[3] }

  def save_issue(markets = nil)
    BetRecommendationGenerator.call(game: game.reload)
    original = BetRecommendationIssue.order(:id).last
    evidence = markets ? original.evidence.merge('markets' => markets) : original.evidence
    BetRecommendationIssue.create!(game:, prediction:, ratings_config_version: version, issued_at: Time.current,
                                   captured_start_time: game.start_time, odds_fetched_at: odds.fetched_at, evidence:)
  end

  def record
    described_class.call(game:)
    BetSettlement.where(game:).order(:bet_type)
  end

  def final
    game.update!(status: :final, home_team_score: 70, away_team_score: 80)
  end

  it 'keeps a unique derived result and immutable source when later quotes and the global model change', :aggregate_failures do
    saved = save_issue
    evidence = saved.attributes
    final
    first = record.map(&:attributes)
    odds.update!(moneyline_away: -500, spread_point: 50, total_points: 200)
    version.update!(current: false)
    create(:ratings_config_version, current: true)
    expect(record.map(&:attributes)).to eq(first)
    expect(saved.reload.attributes).to eq(evidence)
    duplicate = BetSettlement.new(first.first.except('id', 'created_at', 'updated_at'))
    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'clears settled stakes for latest no-play and absent markets, then a newly selected forecast', :aggregate_failures do
    save_issue
    final
    expect(record.sum(&:stake)).to eq(3)
    game.update!(status: :scheduled, home_team_score: nil, away_team_score: nil)
    save_issue('spread' => { 'team' => 'away', 'vegas_line' => 5, 'vegas_odds' => -110,
                             'confidence' => 0.6, 'recommended' => false }, 'moneyline' => nil, 'total' => nil)
    final
    expect(record.pluck(:status, :stake, :net_units)).to eq([['unavailable', 0, nil], ['no_play', 0, nil], ['unavailable', 0, nil]])
    replacement = prediction.dup
    replacement.update!(revision_key: 'replacement', generated_at: 30.minutes.ago)
    expect(record.pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    expect(record.pluck(:prediction_id, :bet_recommendation_issue_id).uniq).to eq([[replacement.id, nil]])
  end

  it 'clears all prior returns for unusable outcomes, status changes and earlier tipoff', :aggregate_failures do
    save_issue
    final
    expect(record.sum(&:stake)).to eq(3)
    [[:final, nil, 80, 'excluded'], [:final, 80, 80, 'excluded'], [:final_unmatched, 70, 80, 'excluded'],
     [:canceled, 70, 80, 'void'], [:scheduled, nil, nil, 'pending']].each do |status, home, away, expected|
      game.update!(status:, home_team_score: home, away_team_score: away)
      expect(record.pluck(:status, :stake, :net_units).uniq).to eq([[expected, 0, nil]])
    end
    game.update!(start_time: 2.hours.ago, status: :final, home_team_score: 70, away_team_score: 80)
    expect(record.pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
  end

  it 'uses fresh participant associations and clears returns after correction or removal', :aggregate_failures do
    save_issue
    final
    expect(record.sum(&:stake)).to eq(3)
    game.home_team_game
    replacement = create(:team_season, season: game.season)
    TeamGame.find(game.home_team_game.id).update!(team: replacement.team, team_season: replacement)
    expect(record.pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    game.reload.away_team_game.destroy!
    expect(record.pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
  end

  it 'retains invalid source evidence with exclusions rather than inventing price or line', :aggregate_failures do
    save_issue('spread' => { 'team' => 'away', 'vegas_line' => nil, 'vegas_odds' => -110, 'confidence' => 0.6, 'recommended' => true },
               'moneyline' => { 'team' => 'away', 'vegas_odds' => 99, 'confidence' => 0.6, 'recommended' => true },
               'total' => { 'team' => 'over', 'vegas_line' => 140, 'vegas_odds' => nil, 'confidence' => 0.6, 'recommended' => true })
    final
    expect(record.pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    expect(record.pluck(:reason).uniq).to eq(['Invalid saved selection, probability, line or price'])
  end

  it 'excludes a latest issue with unverifiable quote timing instead of using the prior issue' do
    prior = save_issue
    invalid = BetRecommendationIssue.create!(prior.attributes.except('id').merge(issued_at: Time.current,
                                                                                 odds_fetched_at: 1.day.from_now))
    final
    expect(record.pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    expect(record.pluck(:bet_recommendation_issue_id).uniq).to eq([invalid.id])
  end
end
