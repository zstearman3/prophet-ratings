# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonReadinessStoredTeam do
  let(:season) { create(:season) }
  let(:model) { RatingsConfigVersion.publish! }
  let!(:first_row) { create(:team_season, season:) }
  let!(:second_row) { create(:team_season, season:) }
  let(:calculator) { ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: model) }

  before { calculator.call }

  it 'retains all captured gaps and unaffected team gaps when one current source cannot be verified' do
    allow(calculator).to receive(:preview_inputs).and_call_original
    allow(calculator).to receive(:preview_inputs).with(first_row).and_raise(ArgumentError, 'Current source unavailable')
    allow(ProphetRatings::PreseasonRatingsCalculator).to receive(:new)
      .with(season, ratings_config_version: model, reviewed_revisions: anything).and_return(calculator)
    gaps = OffseasonReadinessPublication.new(season, model).gaps
    expect(gaps.select { |gap| gap['source'] == 'captured' }.pluck('team_id', 'kind')).to contain_exactly(
      [first_row.team_id, 'recruiting'], [first_row.team_id, 'departures'],
      [second_row.team_id, 'recruiting'], [second_row.team_id, 'departures']
    )
    expect(gaps.select { |gap| gap['source'] == 'current' && gap['team_id'] == second_row.team_id }.pluck('kind'))
      .to contain_exactly('recruiting', 'departures')
    expect(gaps.find { |gap| gap['kind'] == 'inputs' }).to include('team_id' => first_row.team_id, 'source' => 'current',
                                                                   'reason' => /Current source unavailable/)
  end

  it 'retains current gaps with a scoped captured-source error when captured replay cannot be verified' do
    prior = first_row.reload.preseason_prior
    allow(prior).to receive(:inputs).and_return('contract' => 'unsupported-synthetic-contract')
    gaps = described_class.new(first_row, model, snapshot: nil).gaps(calculator)
    expect(gaps.select { |gap| gap['source'] == 'current' }.pluck('kind')).to contain_exactly('recruiting', 'departures')
    expect(gaps.find { |gap| gap['kind'] == 'inputs' }).to include('team_id' => first_row.team_id, 'source' => 'captured')
  end

  it 'rejects a wrong-team capture pointer even when its outputs equal the applied values' do
    first_row.reload.update!(preseason_prior: second_row.reload.preseason_prior)
    snapshot = build(:team_rating_snapshot, team_season: first_row, team: first_row.team, season:, ratings_config_version: model)
    problems = described_class.new(first_row, model, snapshot:).problems
    expect(problems).to include("Team #{first_row.team_id}: capture outputs differ from applied preseason values.")
  end

  it 'rejects a capture missing required output keys even when its remaining values match' do
    prior = first_row.reload.preseason_prior
    allow(prior).to receive(:outputs).and_return('preseason_adj_pace' => first_row.preseason_adj_pace)
    snapshot = build(:team_rating_snapshot, team_season: first_row, team: first_row.team, season:, ratings_config_version: model)
    expect(described_class.new(first_row, model, snapshot:).problems)
      .to include("Team #{first_row.team_id}: capture outputs differ from applied preseason values.")
  end
end
