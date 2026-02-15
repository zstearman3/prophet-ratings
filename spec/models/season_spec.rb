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
end
