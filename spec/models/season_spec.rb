# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Season do
  describe '#update_average_ratings' do
    let(:season) { create(:season) }
    let(:base_time) { Time.zone.parse("#{season.start_date} 12:00") }

    before do
      create_game(home: 'Home One', away: 'Away One', start_time: base_time, status: :final, possessions: 70.0, minutes: 40)
      create_game(home: 'Home One B', away: 'Away One B', start_time: base_time + 1.day, status: :final, possessions: 80.0, minutes: 40)
      create_game(home: 'Home Two', away: 'Away Two', start_time: base_time + 2.days, status: :final, possessions: nil, minutes: nil)
      create_game(
        home: 'Home Three', away: 'Away Three', start_time: base_time + 3.days,
        status: :scheduled, possessions: nil, minutes: nil
      )
    end

    it 'calculates pace deviation from valid final games only' do
      expect { season.update_average_ratings }.not_to raise_error
      expect(season.reload.pace_std_deviation.to_f).to be_within(0.001).of([70.0, 80.0].stdev.to_f)
    end

    def create_game(attrs)
      create(:game,
             season:,
             status: attrs[:status],
             start_time: attrs[:start_time],
             home_team_name: attrs[:home],
             away_team_name: attrs[:away],
             possessions: attrs[:possessions],
             minutes: attrs[:minutes])
    end
  end

  describe '#set_current!' do
    let!(:previous) { create(:season, :current, year: 2026) }
    let(:target) { create(:season, year: 2027) }

    before do
      create(:team_season, season: target, adj_offensive_efficiency: 110, adj_defensive_efficiency: 100, adj_pace: 70)
    end

    it 'switches atomically and preserves timestamps on a repeated activation' do
      target.set_current!
      timestamp = target.reload.updated_at
      target.set_current!
      expect(described_class.current).to eq(target)
      expect(previous.reload).not_to be_current
      expect(target.reload.updated_at).to eq(timestamp)
    end

    it 'preserves the old current season when the target update fails' do
      allow(target).to receive(:update!).with(current: true).and_raise('failed')
      expect { target.set_current! }.to raise_error('failed')
      expect(described_class.current).to eq(previous)
    end

    it 'refuses incomplete ratings without changing current season' do
      target.team_seasons.first.update!(adj_pace: nil)
      expect { target.set_current! }.to raise_error(ArgumentError, /incomplete/)
      expect(described_class.current).to eq(previous)
    end

    it 'refuses activation when preparation is missing a stored team' do
      create(:team)
      expect { target.set_current! }.to raise_error(ArgumentError, /incomplete/)
      expect(described_class.current).to eq(previous)
    end

    it 'fails visibly when another connection holds the scheduled rankings lock' do
      connection = PG.connect(ENV.fetch('TEST_DATABASE_URL'))
      connection.exec_params(
        "SELECT pg_advisory_lock(('x'||substr(md5($1::text), 1, 16))::bit(64)::bigint)",
        [described_class::RATINGS_LOCK_KEY]
      )
      expect { target.set_current! }.to raise_error(Season::OperationInProgress)
      expect(described_class.current).to eq(previous)
    ensure
      connection&.close
    end
  end
end
