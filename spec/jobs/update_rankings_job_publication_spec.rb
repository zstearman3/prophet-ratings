# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateRankingsJob do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  # Exercise publication commits and their real downstream enqueue callback.
  self.use_transactional_tests = false

  let(:season) do
    create(:season, year: 2026, start_date: Date.new(2025, 11, 3), end_date: Date.new(2026, 4, 1))
  end
  let(:version) do
    RatingsConfigVersion.publish!(RatingsConfigVersion.authored_config.merge(
                                    bundle_name: 'scheduled-publication-test', early_season_policy: 'coherent_v1'
                                  ))
  end
  let(:teams) { Array.new(4) { create(:team_season, season:, ratings_config_version: version) } }

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to(Time.utc(2025, 11, 2, 12)) { example.run }
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  before do
    clear_enqueued_jobs
    teams.each { |team| create(:team_alias, team: team.team, value: team.team.school) }
    season.update!(participation_review: {
                     evidence: 'Synthetic roster', reviewed_by: 'Test', unresolved_identities: [],
                     dates: { start_date: '2025-11-03', end_date: '2026-04-01', evidence: 'Synthetic schedule' },
                     teams: teams.map { |team| { team_id: team.team_id, status: 'included', reason: 'Synthetic participant' } }
                   })
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
    season.update!(current: true)
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
    # Captured priors and their applied TeamSeason pointers have reciprocal foreign keys.
    season.team_seasons.each { |team| team.update!(preseason_prior: nil) }
    PreseasonPrior.where(team_season: season.team_seasons).delete_all
    Season.destroy_all
    Team.destroy_all
    RatingsConfigVersion.destroy_all
  end

  def scheduled_game(pair, start_time:)
    game = create(:game, season:, status: :scheduled, start_time:, venue_type: 'neutral',
                         home_team_name: pair.first.team.school, away_team_name: pair.last.team.school)
    pair.each_with_index do |team_season, side|
      create(:team_game, game:, team_season:, team: team_season.team, home: side.zero?,
                         offensive_efficiency: 100, defensive_efficiency: 100)
    end
    game
  end

  def finalized_game(pair, start_time:, pace:)
    scheduled_game(pair, start_time:).tap do |game|
      game.update!(status: :final, possessions: pace, minutes: 40, home_team_score: 70, away_team_score: 60)
    end
  end

  def publish_with_predictions
    described_class.perform_now(season.id, ratings_config_version_id: version.id)
    perform_enqueued_jobs(only: GenerateNightlyPredictionsJob)
  end

  context 'when run on the second morning of the season' do
    let(:snapshots) { season.team_rating_snapshots.where(snapshot_date: Date.new(2025, 11, 3)).order(:team_season_id) }
    let!(:unfinished) { scheduled_game(teams.last(2), start_time: Time.utc(2025, 11, 3, 20)) }
    let!(:forecast_game) { scheduled_game([teams.first, teams.third], start_time: Time.utc(2025, 11, 4, 23)) }
    let(:prediction) { forecast_game.predictions.sole }

    before do
      finalized_game(teams.first(2), start_time: Time.utc(2025, 11, 4, 4, 30), pace: 70) # November 3, 23:30 Eastern.
      finalized_game(teams.first(2), start_time: Time.utc(2025, 11, 4, 5, 30), pace: 90) # November 4, 00:30 Eastern.
      travel_to(Time.utc(2025, 11, 4, 12))
      publish_with_predictions
    end

    it 'publishes only prior-day results with matching model and cutoff evidence' do
      aggregate_failures 'includes yesterday final but excludes today final and unfinished games' do
        expect(snapshots.count).to eq(4)
        expect(season.team_rating_snapshots.where(snapshot_date: Date.new(2025, 11, 4))).to be_empty
        # One finalized regulation game contributes 70, not the leaked two-game average of 80.
        expect(teams.first(2).map { |team| team.reload.pace.to_f }).to eq([70, 70])
        expect(teams.first(2).map { |team| team.wins + team.losses }).to eq([1, 1])
        expect(teams.last(2).map { |team| team.reload.pace }).to eq([nil, nil])
      end

      aggregate_failures 'publishes matching model, date and cutoff evidence for season inputs and coherent anchors' do
        snapshots.each do |snapshot|
          expect(snapshot.ratings_config_version_id).to eq(version.id)
          expect(snapshot.stats.fetch('rating_anchors')).to include('as_of' => '2025-11-03', 'model_version_id' => version.id)
          expect(snapshot.stats.fetch('season_forecast_inputs')).to include(
            'snapshot_date' => '2025-11-03', 'result_cutoff' => '2025-11-03', 'season_id' => season.id, 'model_version_id' => version.id
          )
        end
      end
    end

    it 'issues a frozen forecast from prior-day inputs and reuses unchanged retries' do
      aggregate_failures 'uses the new prior-day publication and frozen season inputs for today pregame forecast' do
        expect(prediction).to have_attributes(forecast_kind: 'pregame', input_cutoff: Date.new(2025, 11, 3),
                                              ratings_config_version_id: version.id)
        expect([prediction.home_team_snapshot, prediction.away_team_snapshot]).to eq(snapshots.to_a.values_at(0, 2))
        expect(prediction.calculation_context.fetch('season_source')).to include(
          'snapshot_date' => '2025-11-03', 'result_cutoff' => '2025-11-03', 'source' => 'publication'
        )
        expect(prediction.calculation_context.fetch('season')).to eq(snapshots.first.stats.dig('season_forecast_inputs', 'values'))
        expect(unfinished.predictions).to be_empty
      end

      aggregate_failures 'records actual morning issuance after source creation and correction timestamps' do
        expect(prediction.generated_at).to eq(Time.utc(2025, 11, 4, 12))
        sources = [prediction.home_team_snapshot, prediction.away_team_snapshot]
        expect(sources).to all(have_attributes(created_at: be <= prediction.generated_at, updated_at: be <= prediction.generated_at))
      end

      aggregate_failures 'reuses unchanged publication and forecast identities without replacing captured context' do
        snapshot_ids = snapshots.pluck(:id)
        prediction_id = prediction.id
        context = prediction.calculation_context
        travel 1.minute
        publish_with_predictions
        expect(snapshots.reload.pluck(:id)).to eq(snapshot_ids)
        expect(forecast_game.predictions.pluck(:id)).to eq([prediction_id])
        expect(prediction.reload.calculation_context).to eq(context)
      end
    end
  end

  it 'publishes the pre-opening date on opening morning without including an already-final opening game' do
    finalized_game(teams.first(2), start_time: Time.utc(2025, 11, 3, 5, 30), pace: 90)
    forecast_game = scheduled_game(teams.last(2), start_time: Time.utc(2025, 11, 3, 23))
    travel_to(Time.utc(2025, 11, 3, 12))

    publish_with_predictions

    expect(season.team_rating_snapshots.pluck(:snapshot_date).uniq).to eq([Date.new(2025, 11, 2)])
    expect(teams.first(2).map { |team| team.reload.pace }).to eq([nil, nil])
    prediction = forecast_game.predictions.sole
    expect(prediction).to have_attributes(forecast_kind: 'pregame', input_cutoff: Date.new(2025, 11, 2))
    expect(prediction.home_team_snapshot.stats.fetch('rating_anchors')).to include('as_of' => '2025-11-02')
    expect(prediction.calculation_context.fetch('season_source')).to include('result_cutoff' => '2025-11-02')
  end

  it 'keeps missing-participant predictions unsaved with a useful warning after successful publication' do
    game = create(:game, season:, status: :scheduled, start_time: Time.utc(2025, 11, 3, 23))
    allow(Rails.logger).to receive(:warn)
    travel_to(Time.utc(2025, 11, 3, 12))

    publish_with_predictions

    expect(game.predictions).to be_empty
    expect(Rails.logger).to have_received(:warn).with(/game=#{game.id}: missing or invalid rating inputs \(prior-day only\)/)
    expect(season.team_rating_snapshots.count).to eq(4)
  end
end
