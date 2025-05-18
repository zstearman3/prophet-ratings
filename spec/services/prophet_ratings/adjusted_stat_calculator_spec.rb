# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::AdjustedStatCalculator, type: :service do
  describe '#run' do
    let(:season) { create(:season) }
    let!(:team_seasons) { create_three_team_round_robin(season:, stat: :effective_fg_percentage) }

    let(:ts1) { team_seasons[0] }
    let(:ts2) { team_seasons[1] }
    let(:ts3) { team_seasons[1] }

    before do
      allow_any_instance_of(described_class).to receive(:average_stat_for_season).and_return(0.50)

      described_class.new(
        season:,
        raw_stat: :effective_fg_percentage,
        adj_stat: :adj_effective_fg_percentage,
        adj_stat_allowed: :adj_effective_fg_percentage_allowed
      ).call

      [ts1, ts2, ts3].each(&:reload)
    end

    it 'assigns higher adj eFG% to stronger offensive teams' do
      expect(ts1.adj_effective_fg_percentage).to be > 0.50
      expect(ts2.adj_effective_fg_percentage).to be < 0.50
    end

    it 'assigns lower adj eFG% allowed to stronger defensive teams' do
      expect(ts1.adj_effective_fg_percentage_allowed).to be_within(0.01).of(0.50)
      expect(ts3.adj_effective_fg_percentage_allowed).to be > 0.50
    end
  end
end
