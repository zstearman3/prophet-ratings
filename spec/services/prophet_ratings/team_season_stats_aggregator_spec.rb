# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::TeamSeasonStatsAggregator, type: :service do
  before { RatingsConfigVersion.publish! }

  include StatsHelpers

  describe '#run' do
    let(:team) { create(:team) }
    let(:season) { create(:season, :current) }
    let(:team_season) { create(:team_season, team:, season:) }
    let(:baseline_volatility) { Rails.application.config_for(:ratings).baseline_volatility }

    before do
      opponents = create_list(:team, 3)
      games = [
        create(:game, season:, start_time: season.end_date - 12.days, home_team_name: team.school,
                      away_team_name: opponents[0].school),
        create(:game, season:, start_time: season.end_date - 9.days, home_team_name: team.school,
                      away_team_name: opponents[1].school),
        create(:game, season:, start_time: season.end_date - 6.days, home_team_name: team.school,
                      away_team_name: opponents[2].school)
      ]
      team_games = games.each_with_index.map do |game, i|
        create(:team_game,
               team:,
               team_season:,
               game:,
               opponent_team_season: create(:team_season, team: opponents[i], season:),
               field_goals_made: 20,
               field_goals_attempted: 40,
               three_pt_made: 10,
               three_pt_attempted: 18,
               two_pt_made: 10,
               two_pt_attempted: 22,
               offensive_rebounds: 8,
               free_throws_attempted: 12,
               turnovers: 10,
               minutes: 200,
               assists: 12,
               steals: 5,
               blocks: 3)
      end
      team_games.each do |tg|
        tg.game.update!(home_team_score: 70, away_team_score: 65)
      end

      team_games.each(&:calculate_game_stats)

      described_class.new(season:).run
      team_season.reload
    end

    it 'computes effective_fg_percentage correctly' do
      fgm = 20 * 3
      fga = 40 * 3
      three_pm = 10 * 3
      expected = expected_effective_fg_percentage(fgm:, fga:, three_pm:)

      expect(team_season.effective_fg_percentage).to be_within(0.001).of(expected)
    end

    it 'averages turnover_rate across games' do
      individual_rate = expected_turnover_rate(
        tov: 10,
        possessions: expected_possessions(fga: 40, orb: 8, tov: 10, fta: 12)
      )
      expected_avg = individual_rate # all games identical

      expect(team_season.turnover_rate).to be_within(0.001).of(expected_avg)
    end

    it 'sets baseline volatility and home boost values for teams with no finalized games' do
      idle_team_season = create(
        :team_season,
        season:,
        offensive_efficiency_volatility: nil,
        defensive_efficiency_volatility: nil,
        home_offense_boost: nil,
        home_defense_boost: nil
      )

      described_class.new(season:).run
      idle_team_season.reload

      expect(idle_team_season.offensive_efficiency_volatility).to eq(11.5)
      expect(idle_team_season.defensive_efficiency_volatility).to eq(11.5)
      expect(idle_team_season.home_offense_boost).to eq(2.2)
      expect(idle_team_season.home_defense_boost).to eq(-2.2)
    end

    it 'ignores predictions with missing home efficiency errors when calculating home boosts' do
      ratings_config_version = create(:ratings_config_version)
      opponent_team_season = create(:team_season, season:)
      create_prediction_with_snapshots(
        opponent_team_season:,
        ratings_config_version:,
        game: team_season.team_games.first.game,
        snapshot_date: season.end_date - 7.days,
        attrs: {
          home_snapshot: {
            home_offense_boost: nil,
            home_defense_boost: nil
          },
          prediction: {
            home_offensive_efficiency_error: nil,
            home_defensive_efficiency_error: nil
          }
        }
      )

      expect { described_class.new(season:).run }.not_to raise_error

      team_season.reload
      expect(team_season.home_offense_boost).to eq(2.2)
      expect(team_season.home_defense_boost).to eq(-2.2)
    end

    it 'uses only non-nil errors when calculating volatility sample sizes' do
      4.times do |i|
        opponent_team_season = create(:team_season, season:)
        create_prediction_with_snapshots(
          opponent_team_season:,
          ratings_config_version: create(:ratings_config_version),
          game: create(
            :game,
            season:,
            start_time: season.end_date - (5 - i).days,
            home_team_name: team.school,
            away_team_name: opponent_team_season.team.school
          ),
          snapshot_date: season.end_date - (10 + i).days,
          attrs: {
            prediction: {
              home_offensive_efficiency_error: nil,
              away_offensive_efficiency_error: nil,
              home_defensive_efficiency_error: nil,
              away_defensive_efficiency_error: nil,
              pace_error: nil
            }
          }
        )
      end

      described_class.new(season:).run
      team_season.reload

      expect(team_season.offensive_efficiency_volatility).to eq(baseline_volatility[:efficiency_volatility].to_f)
      expect(team_season.defensive_efficiency_volatility).to eq(baseline_volatility[:efficiency_volatility].to_f)
      expect(team_season.pace_volatility).to eq(baseline_volatility[:pace_volatility].to_f)
    end

    def create_prediction_with_snapshots(opponent_team_season:, ratings_config_version:, game:, snapshot_date:,
                                         attrs: {})
      home_snapshot_attrs = attrs.fetch(:home_snapshot, {})
      prediction_attrs = attrs.fetch(:prediction, {})

      home_snapshot = create(
        :team_rating_snapshot,
        team_season: team_season,
        team: team,
        season: season,
        ratings_config_version:,
        snapshot_date:,
        **home_snapshot_attrs
      )
      away_snapshot = create(
        :team_rating_snapshot,
        team_season: opponent_team_season,
        team: opponent_team_season.team,
        season: season,
        ratings_config_version:,
        snapshot_date:
      )

      create(
        :prediction,
        game:,
        home_team_snapshot: home_snapshot,
        away_team_snapshot: away_snapshot,
        ratings_config_version:,
        **prediction_attrs
      )
    end
  end

  describe 'completed unmatched records' do
    it 'counts score-based home wins and away losses through the cutoff without changing model aggregates' do
      season = create(:season)
      version = RatingsConfigVersion.published_default
      team_season = create(:team_season, season:)
      cutoff = season.start_date + 10.days
      aggregator = described_class.new(season:, as_of: cutoff, ratings_config_version: version)
      final = create(:game, season:, home_team_score: 70, away_team_score: 60,
                            possessions: 70, minutes: 40, start_time: Game.schedule_time_for(cutoff - 1.day))
      create(:team_game, game: final, team_season:, team: team_season.team, home: true,
                         offensive_rating: 100, defensive_rating: 90, field_goals_made: 20,
                         field_goals_attempted: 40, three_pt_made: 10, three_pt_attempted: 20,
                         turnover_rate: 0.1)
      aggregator.run
      baseline = team_season.reload.attributes
      [true, false, true].each_with_index do |home, index|
        game = create(:game, season:, status: :final_unmatched, home_team_score: 100, away_team_score: 90,
                             in_conference: true, possessions: 200, minutes: 40, away_team_name: "Unknown #{index}",
                             start_time: Game.schedule_time_for(index == 2 ? cutoff + 1.day : cutoff))
        create(:team_game, game:, team_season:, team: team_season.team, home:,
                           offensive_rating: 999, defensive_rating: 999, field_goals_made: 999,
                           field_goals_attempted: 999, three_pt_made: 999, three_pt_attempted: 999,
                           turnover_rate: 0.9)
      end
      aggregator.run
      expect(team_season.reload).to have_attributes(wins: 2, losses: 1, conference_wins: 0, conference_losses: 0)
      expect(team_season.attributes.except('wins', 'losses')).to eq(baseline.except('wins', 'losses'))
    end
  end
end
