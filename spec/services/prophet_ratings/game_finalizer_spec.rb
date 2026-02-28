# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GameFinalizer, type: :service do
  describe '#finalize_prediction!' do
    it 'does not update prediction when error attributes are unavailable' do
      prediction = instance_double(Prediction)
      predictions_relation = instance_double(ActiveRecord::Associations::CollectionProxy)
      game = instance_double(Game, predictions: predictions_relation)
      finalizer = described_class.new(game)

      allow(predictions_relation).to receive(:find_by).and_return(prediction)
      allow(finalizer).to receive_messages(
        home_snapshot: instance_double(TeamRatingSnapshot),
        away_snapshot: instance_double(TeamRatingSnapshot)
      )
      allow(finalizer).to receive(:prediction_error_attributes).with(prediction).and_return(nil)
      allow(prediction).to receive(:update!)

      finalizer.send(:finalize_prediction!)

      expect(prediction).not_to have_received(:update!)
    end
  end

  describe '#calculated_neutrality' do
    subject(:calculated_neutrality) { described_class.new(game).send(:calculated_neutrality) }

    let(:season) { create(:season) }
    let(:home_team) do
      create(
        :team,
        school: 'Home School',
        slug: 'home-school',
        location: 'Home City, HS',
        home_venue: 'Home Arena'
      )
    end
    let(:away_team) { create(:team, school: 'Away School', slug: 'away-school') }
    let(:home_team_season) { create(:team_season, season:, team: home_team) }
    let(:away_team_season) { create(:team_season, season:, team: away_team) }
    let(:location) { 'Neutral Court' }
    let(:neutral) { nil }
    let(:game) do
      create(
        :game,
        season:,
        status: :final,
        start_time: season.start_date + 1.day,
        home_team_name: home_team.school,
        away_team_name: away_team.school,
        location:,
        neutral:
      )
    end

    before do
      create(:team_game, game:, team: home_team, team_season: home_team_season, home: true)
      create(:team_game, game:, team: away_team, team_season: away_team_season, home: false)
    end

    context 'when location is unknown and no override exists' do
      let(:location) { '' }

      it 'defaults to non-neutral' do
        expect(calculated_neutrality).to be(false)
      end
    end

    context 'when location is unknown and game neutrality is explicitly set' do
      let(:location) { nil }
      let(:neutral) { true }

      it 'preserves the explicit override' do
        expect(calculated_neutrality).to be(true)
      end
    end

    context 'when location is the home venue' do
      let(:location) { 'Home Arena' }

      it 'is not neutral' do
        expect(calculated_neutrality).to be(false)
      end
    end

    context 'when location is away from home city and venue' do
      let(:location) { 'Neutral Court' }

      it 'is neutral' do
        expect(calculated_neutrality).to be(true)
      end
    end
  end
end
