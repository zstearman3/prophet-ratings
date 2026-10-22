# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduleReadiness do
  it 'retains reasoned deferral history and requires reassessment only after target-season usable games appear' do
    season = create(:season, year: 2027)
    admin = create(:user, :admin)
    deferral = ScheduleDeferral.create!(season:, requested_by: admin, reason: 'Awaiting published schedule')
    readiness = described_class.new(season)
    expect(readiness.summary).to include('Prediction readiness deferred', admin.email, deferral.reason)
    other = create(:season, year: 2028)
    game = create(:game, season: other, status: :scheduled)
    [true, false].each do |home|
      membership = create(:team_season, season: other)
      create(:team_game, game:, team_season: membership, team: membership.team, home:)
    end
    expect(readiness).not_to be_usable
    game.update!(season:)
    aggregate_failures do
      expect(readiness).to be_usable
      expect(readiness.summary).to include('reassessment needed', deferral.reason)
      expect(ScheduleDeferral.new(season:, requested_by: admin, reason: 'Again')).not_to be_valid
      expect { deferral.update!(reason: 'Changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
