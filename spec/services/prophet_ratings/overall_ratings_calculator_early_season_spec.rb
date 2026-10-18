# frozen_string_literal: true

require 'rails_helper'

# REAL_SOLVER=true bin/test ... runs the full Rails/Python boundary with synthetic data only.
RSpec.describe ProphetRatings::OverallRatingsCalculator do
  let(:season) { create(:season) }
  let(:policy) { 'coherent_v1' }
  let(:prior_efficiencies) { nil }
  let(:recency_floor) { 1 }
  let(:version) do
    payload = RatingsConfigVersion.authored_config
    payload[:bundle_name] = 'early-season-test'
    payload[:early_season_policy] = policy
    payload[:preseason][:previous_season_weight] = 1
    payload[:ridge][:alpha] = 1
    payload[:weighting][:min_recency_weight] = recency_floor
    RatingsConfigVersion.publish!(payload)
  end
  let(:calculator) { described_class.new(season, ratings_config_version: version) }
  let!(:teams) do
    rows = Array.new(5) { create(:team_season, season:, ratings_config_version: version) }
    if prior_efficiencies
      previous = create(:season, year: season.year - 1)
      rows.each_with_index do |row, index|
        create(:team_season, season: previous, team: row.team, adj_offensive_efficiency: prior_efficiencies[index],
                             adj_defensive_efficiency: 220 - prior_efficiencies[index], adj_pace: 70)
      end
    end
    rows
  end

  before do
    teams.each { |team| create(:team_alias, team: team.team, value: team.team.school) }
    season.update!(participation_review: {
                     evidence: 'Synthetic roster', reviewed_by: 'Test', unresolved_identities: [],
                     dates: { start_date: season.start_date.iso8601, end_date: season.end_date.iso8601, evidence: 'Synthetic schedule' },
                     teams: teams.map { |team| { team_id: team.team_id, status: 'included', reason: 'Synthetic participant' } }
                   })
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
    unless ENV['REAL_SOLVER'] == 'true'
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python) { |rows, _targets, **| Array.new(rows.first.size, 0.0) }
    end
  end

  def games_between(pair, efficiencies: [120, 120], date: season.start_date, pace: 80)
    2.times do |index|
      game = create(:game, season:, start_time: Game.schedule_time_for(date + index) + 12.hours,
                           possessions: pace, minutes: 40, home_team_score: 80, away_team_score: 70,
                           venue_type: 'neutral', venue_confidence: 'confirmed',
                           home_team_name: pair.first.team.school, away_team_name: pair.last.team.school)
      pair.each_with_index do |team_season, side|
        create(:team_game, game:, team_season:, team: team_season.team, home: side.zero?,
                           offensive_efficiency: efficiencies[side], defensive_efficiency: efficiencies[1 - side],
                           effective_fg_percentage: nil, turnover_rate: nil, offensive_rebound_rate: nil,
                           free_throw_rate: nil, field_goals_attempted: 0, three_pt_attempted: 0)
      end
    end
  end

  def snapshots(date)
    teams.map { |team| team.team_rating_snapshots.find_by!(snapshot_date: date) }
  end

  def predict(pair)
    ProphetRatings::GamePredictor.new(home_rating_snapshot: pair.first, away_rating_snapshot: pair.last,
                                      season:, venue: { type: 'neutral', confidence: 'confirmed' }).call
  end

  it 'updates qualified teams on day one with unplayed participants and preserves coherent mixed anchors' do
    games_between(teams.first(2))
    date = season.start_date + 1
    calculator.call(as_of: date)
    updated, _other, unplayed = snapshots(date)
    # Day one keeps .975 prior: .975*105.5 + .025*120 = 105.8625, rounded on persistence.
    expect([updated.adj_offensive_efficiency.to_f, updated.stats.dig('rating_anchors', 'adj_offensive_efficiency')])
      .to eq([105.863, 105.8625])
    expect(unplayed.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'adj_pace')).to eq([105.5, 105.5, 69.5])
    expect(unplayed.stats.dig('rating_anchors', 'adj_offensive_efficiency')).to eq(105.5)
    expect(predict([unplayed, snapshots(date).last])[:home_expected_score]).to eq(73.32)
    expect(predict([updated, unplayed])[:meta][:home_expected_ortg]).to eq(105.68)
  end

  it 'keeps day zero entirely on the captured prior and transitions through the blend floor deterministically' do
    games_between(teams.first(2))
    [[0, 105.5, 69.5], [20, 112.75, 74.75], [40, 118.55, 78.95], [80, 118.55, 78.95]].each do |day, efficiency, pace|
      date = season.start_date + day
      calculator.call(as_of: date)
      snapshot = snapshots(date).first
      expect(snapshot.adj_offensive_efficiency).to eq(efficiency)
      expect(snapshot.adj_pace).to eq(pace)
      expect(snapshot.stats.dig('rating_anchors', 'adj_pace')).to eq(pace)
      expect(predict(snapshots(date).first(2))[:home_expected_score]).to eq((efficiency * pace / 100).round(2))
      before = snapshot.attributes.except('updated_at')
      calculator.call(as_of: date)
      expect(snapshot.reload.attributes.except('updated_at')).to eq(before)
    end
  end

  it 'does not run an anchor-only solve for disconnected eligible teams or missing per-stat observations' do
    # Each eligible team has two finals, but never against an eligible opponent.
    games_between([teams[0], teams[2]])
    games_between([teams[1], teams[3]])
    TeamGame.where(team_season: teams.values_at(2, 3)).delete_all
    calculator.call(as_of: season.start_date + 1)
    expect(StatisticsUtils).not_to have_received(:solve_least_squares_with_python) unless ENV['REAL_SOLVER'] == 'true'
    expect(teams.map { |team| team.reload.adj_offensive_efficiency }).to eq(Array.new(5, 105.5))
  end

  it 'retains captured priors when finalized games contain no usable efficiency or pace' do
    games_between(teams.first(2), pace: nil)
    TeamGame.update_all(offensive_efficiency: nil, defensive_efficiency: nil) # rubocop:disable Rails/SkipsModelValidations
    calculator.call(as_of: season.start_date + 1)
    expect(teams.map { |team| team.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'adj_pace') })
      .to eq(Array.new(5, [105.5, 105.5, 69.5]))
    expect(StatisticsUtils).not_to have_received(:solve_least_squares_with_python) unless ENV['REAL_SOLVER'] == 'true'
  end

  it 'leaves unsupported factor columns missing while other qualified teams have usable factor observations' do
    games_between(teams.first(2))
    games_between(teams.values_at(2, 3))
    teams[2].update!(adj_effective_fg_percentage: 0.9)
    TeamGame.where(team_season: teams.first(2)).update_all( # rubocop:disable Rails/SkipsModelValidations
      effective_fg_percentage: 0.5, field_goals_made: 25, field_goals_attempted: 50, three_pt_made: 0
    )
    calculator.call(as_of: season.start_date + 1)
    expect(teams.first(2).map { |team| team.reload.adj_effective_fg_percentage }).to eq([0.5, 0.5])
    expect(teams.last(3).map { |team| team.reload.adj_effective_fg_percentage }).to all(be_nil)
  end

  context 'with expired observation weights' do
    let(:recency_floor) { 0 }

    it 'retains coherent priors rather than publishing a regularizer-only solution' do
      games_between(teams.first(2))
      calculator.call(as_of: season.start_date + 100)
      expect(teams.map { |team| team.reload.adj_offensive_efficiency }).to eq(Array.new(5, 105.5))
      expect(StatisticsUtils).not_to have_received(:solve_least_squares_with_python) unless ENV['REAL_SOLVER'] == 'true'
    end
  end

  it 'retains a one-game teams prior while two-game teams update' do
    games_between(teams.first(2))
    games_between(teams.last(2))
    season.games.order(:id).last.destroy!
    calculator.call(as_of: season.start_date + 1)
    expect(teams.last(2).map { |team| team.reload.adj_offensive_efficiency }).to eq([105.5, 105.5])
    expect(teams.first.reload.adj_offensive_efficiency).to be > 105.5
  end

  it 'solves disconnected schedules with positive ridge and independently known coefficients' do
    games_between(teams.first(2), efficiencies: [124, 116])
    games_between(teams.values_at(2, 3))
    unless ENV['REAL_SOLVER'] == 'true'
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python) do |rows, targets, **|
        targets.any?(&:nonzero?) ? [1.6, -1.6, 0, 0, -1.6, 1.6, 0, 0] : Array.new(rows.first.size, 0.0)
      end
    end
    calculator.call(as_of: season.start_date + 20)
    # Two unit-weight observations of +4: each of the two coefficients is 8/(4+ridge=5)=1.6.
    expect(teams.first.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'rating'))
      .to eq([113.55, 111.95, 1.6])
    expect(teams.last.reload.adj_offensive_efficiency).to eq(105.5)
    expect(teams.map { |team| team.reload.overall_rank }).to contain_exactly(1, 2, 3, 4, 5)
  end

  it 'rolls back live priors, anchors, aggregates and snapshots after a later solve fails' do
    games_between(teams.first(2))
    original = [season.reload.attributes, teams.map { |team| team.reload.attributes }, season.team_rating_snapshots.map(&:attributes)]
    calls = 0
    allow(StatisticsUtils).to receive(:solve_least_squares_with_python) do |rows, _targets, **|
      calls += 1
      raise 'pace solve failed' if calls == 2

      Array.new(rows.first.size, 0.0)
    end
    expect { calculator.call(as_of: season.start_date + 1) }.to raise_error('pace solve failed')
    expect([season.reload.attributes, teams.map { |team| team.reload.attributes }, season.team_rating_snapshots.map(&:attributes)])
      .to eq(original)
  end

  it 'freezes snapshot anchors for predictions, simulations and forecast replay despite later season mutations' do
    games_between(teams.first(2))
    date = season.start_date + 1
    calculator.call(as_of: date)
    pair = snapshots(date).first(2)
    game = create(:game, season:, venue_type: 'neutral', venue_confidence: 'confirmed')
    context = ProphetRatings::ForecastContext.capture(game, pair, version)
    expected = predict(pair)
    season.update!(average_efficiency: 150, average_pace: 100)
    reconstructed = pair.map { |snapshot| ProphetRatings::HistoricalRatingsState.snapshot(snapshot.team_season, date) }
    expect([predict(pair), predict(reconstructed)]).to eq([expected, expected])
    expect(ProphetRatings::ForecastContext.new(context).predictor.call).to eq(expected)
    allow(ProphetRatings::Gaussian).to receive(:new) { |mean, _sd| instance_double(ProphetRatings::Gaussian, rand: mean) }
    simulation = ProphetRatings::GameSimulator.new(home_rating_snapshot: pair.first, away_rating_snapshot: pair.last,
                                                   season:, neutral: true).call
    expect(simulation[:home_score]).to eq(expected[:home_expected_score])
    pair.first.update!(stats: pair.first.stats.except('rating_anchors'))
    expect { predict(pair) }.to raise_error(ArgumentError, /stored rating anchors/)
    expect(ProphetRatings::ForecastContext.new(context).predictor.call).to eq(expected)
  end

  it 'combines snapshots from different dates using their own stored efficiency and pace centers' do
    games_between(teams.first(2))
    calculator.call(as_of: season.start_date + 20)
    home = snapshots(season.start_date + 20).first
    away = snapshots(season.start_date - 1).last
    season.update!(average_efficiency: 150, average_pace: 100)
    result = predict([home, away])
    # Centers: (112.75+105.5)/2=109.125 and (74.75+69.5)/2=72.125. Score=78.70640625.
    expect(result.values_at(:home_expected_score, :away_expected_score)).to eq([78.71, 78.71])
    expect(result[:meta].values_at(:home_expected_ortg, :expected_pace)).to eq([109.13, 72.13])
  end

  it 'rejects snapshot publication on a date without matching live anchors' do
    expect do
      ProphetRatings::TeamRatingSnapshotService.new(season:, ratings_config_version: version, as_of: season.start_date).call
    end.to raise_error(ArgumentError, /publication date/)
  end

  context 'with unequal captured priors' do
    let(:prior_efficiencies) { [120, 100, 110, 110, 110] }

    it 'blends the common prior center rather than using the teams individual strength as an anchor' do
      games_between(teams.first(2))
      calculator.call(as_of: season.start_date + 1)
      updated, other, unplayed = snapshots(season.start_date + 1)
      expect([updated.adj_offensive_efficiency, updated.adj_defensive_efficiency]).to eq([120, 100.5])
      expect(updated.stats.dig('rating_anchors', 'adj_offensive_efficiency')).to eq(110.25)
      expect(unplayed.stats.dig('rating_anchors', 'adj_offensive_efficiency')).to eq(110)
      expect(predict([updated, other])[:meta][:home_expected_ortg]).to eq(129.75)
      expect(predict([updated, unplayed])[:meta][:home_expected_ortg]).to eq(119.88)
    end
  end

  context 'without the early-season policy' do
    let(:policy) { nil }

    it 'preserves the calendar gate, mutable raw efficiency anchor and original predictions' do
      games_between(teams.first(2))
      calculator.call(as_of: season.start_date + 1)
      expect(teams.first.reload.adj_offensive_efficiency).to eq(105.5)
      expect(season.reload.average_efficiency).to eq(120)
      expect(predict(snapshots(season.start_date + 1).first(2))[:home_expected_score]).to eq(63.25)
      expect(snapshots(season.start_date + 1).first.stats).not_to have_key('rating_anchors')
    end
  end

  it 'requires positive ridge for core and factors before a model can be published' do
    %i[core factor].each do |stat|
      payload = version.config.deep_symbolize_keys.deep_dup
      payload[:bundle_name] = "zero-ridge-#{stat}"
      stat == :core ? payload[:ridge][:alpha] = 0 : payload[:factors][:turnover_rate][:ridge_alpha] = 0
      expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError, /positive ridge/)
    end
  end
end
