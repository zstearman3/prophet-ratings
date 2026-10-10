# frozen_string_literal: true

require 'rails_helper'

# Run in Docker with REAL_SOLVER=true to exercise Python/NumPy using only these synthetic records.
RSpec.describe ProphetRatings::AdjustedStatCalculator do
  before { RatingsConfigVersion.publish! }

  let(:season) { create(:season) }
  let(:as_of) { season.start_date + 30 }
  let(:rows) { create_three_team_round_robin(season:, stat: :offensive_efficiency, date: as_of) }

  def prepare_reviewed_fixture
    included = rows.first(2)
    rows.each_with_index { |row, index| row.update!(offensive_efficiency: index == 2 ? 900 : 100) }
    TeamGame.where(team_season: included).find_each { |game| game.update!(offensive_efficiency: 100) }
    season.update!(participation_review: {
                     evidence: 'Synthetic roster', reviewed_by: 'Test', unresolved_identities: [],
                     dates: { start_date: season.start_date.iso8601, end_date: season.end_date.iso8601, evidence: 'Test schedule' },
                     teams: rows.map.with_index do |row, index|
                       { team_id: row.team_id, status: index == 2 ? 'excluded' : 'included', reason: 'Verified synthetic decision' }
                     end
                   })
    included
  end

  it 'uses only included teams and their baseline in the solver matrix and leaves excluded stats untouched' do
    included = prepare_reviewed_fixture
    original = rows.last.reload.attributes
    # Equal 100 efficiencies and a 100 league anchor give zero effects for every included team/side.
    allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_return([0.0, 0.0, 0.0, 0.0]) unless ENV['REAL_SOLVER'] == 'true'
    described_class.new(season:, raw_stat: :offensive_efficiency, adj_stat: :adj_offensive_efficiency,
                        adj_stat_allowed: :adj_defensive_efficiency, as_of:).call
    unless ENV['REAL_SOLVER'] == 'true'
      expect(StatisticsUtils).to have_received(:solve_least_squares_with_python) do |matrix, observations, **|
        expect(matrix.map(&:size).uniq).to eq([4])
        expect(observations).to eq([0.0, 0.0, 0.0])
      end
    end
    expect(included.map { |row| row.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency') })
      .to eq([[100, 100], [100, 100]])
    expect(rows.last.reload.attributes).to eq(original)
  end
end
