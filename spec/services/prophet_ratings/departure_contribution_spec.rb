# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::DepartureContribution do
  let(:config) do
    RatingsConfigVersion.authored_config.deep_dup.tap do |payload|
      payload[:preseason][:departures] = YAML.load_file(Rails.root.join('config/examples/departures_r3.yml')).symbolize_keys
    end
  end
  let(:inputs) do
    { team_id: 1, target_year: 2026, previous_values: { adj_offensive_efficiency: 100, adj_defensive_efficiency: 110 },
      profile_values: {}, reviewed_departures: evidence }
  end
  let(:evidence) do
    { draft_year: 2025, prior_season_year: 2025, target_year: 2026, expected_picks: (1..60).to_a, failures: [],
      review: { decision: 'approved', reviewed_by: 'Test reviewer', reviewed_at: '2026-10-14T12:00:00Z' },
      selections: (1..60).map { |pick| selection(pick) } }
  end

  def selection(pick)
    { selection_key: "2025/#{pick}", overall_pick: pick, status: 'verified_no_college',
      reason: 'Synthetic reviewed evidence', stints: [], candidate_team_ids: [] }
  end

  def departure(pick, points, denominator = 2000)
    row = evidence[:selections][pick - 1]
    row[:status] = 'eligible_prior_season'
    row[:stints] = [{ source_id: 'school', player_source_url: "https://school.example/player/#{pick}", team_id: 1,
                      player_points: points, team_points: denominator, games: 2, scope: Departures::Contract::SCOPE,
                      units: Departures::ProductionStint::UNITS }]
  end

  def score
    described_class.new(inputs, config).call
  end

  [[200, -0.2], [800, -0.8], [1000, -1], [2000, -1]].each do |points, expected|
    it "scores later pick 60's #{points}/2000 points as #{expected} net efficiency" do
      departure(60, points)
      expect(score).to include(contribution: expected, loss_share: points / 2000.0, reason: 'eligible',
                               formula: 'points_share_v1', units: 'net_points_per_100_possessions')
    end
  end

  it 'aggregates actual limited participation once per player without pick or team-strength weighting' do
    departure(1, 500)
    departure(60, 300)
    expect(score).to include(loss_share: 0.4, raw_contribution: -0.8, contribution: -0.8)
    inputs[:previous_values] = { adj_offensive_efficiency: 130, adj_defensive_efficiency: 90 }
    expect(score[:contribution]).to eq(-0.8)
  end

  it 'distinguishes no eligible participation and actual zero-point participation from unknown' do
    expect(score).to include(loss_share: 0, contribution: 0, reason: 'verified_zero')
    evidence[:selections].last[:status] = 'verified_nonparticipant'
    expect(score[:reason]).to eq('verified_zero')
    departure(60, 0)
    expect(score[:reason]).to eq('verified_zero')
  end

  it 'keeps partial/global identity coverage unknown while exposing known subtotals and exclusions' do
    departure(60, 500)
    evidence[:selections][0][:status] = 'unresolved_identity'
    expect(score).to include(loss_share: nil, contribution: 0, reason: 'unknown_partial_coverage')
    expect(score[:coverage]).to include('known_points_subtotal' => 500)
    expect(score[:inputs].dig('reviewed_departures', 'selections').first['status']).to eq('unresolved_identity')
  end

  it 'localizes unknown production when the team identity is resolved' do
    evidence[:selections][0].merge!(status: 'unknown_production', candidate_team_ids: [2])
    expect(score[:reason]).to eq('verified_zero')
    evidence[:selections][0][:candidate_team_ids] = [1]
    expect(score).to include(loss_share: nil, contribution: 0)
  end

  it 'does not invent zero for missing evidence, incomplete picks or failed sources' do
    evidence[:selections].pop
    expect(score[:loss_share]).to be_nil
    evidence[:selections] << selection(60)
    evidence[:failures] << { id: 'failed-source' }
    expect(score[:loss_share]).to be_nil
    inputs[:reviewed_departures] = nil
    expect(score).to include(loss_share: nil, contribution: 0, reason: 'missing_departure_evidence')
  end

  it 'suppresses effect for either missing previous core while preserving known loss' do
    departure(60, 800)
    %i[adj_offensive_efficiency adj_defensive_efficiency].each do |stat|
      captured = inputs.deep_dup
      captured[:previous_values][stat] = nil
      expect(described_class.new(captured, config).call).to include(loss_share: 0.4, contribution: 0,
                                                                    reason: 'no_complete_previous_core')
    end
  end

  it 'applies zero/fractional weight once and retains uncapped/capped arithmetic' do
    departure(60, 2000)
    config[:preseason][:departures][:weight] = 0
    expect(score).to include(contribution: 0, raw_contribution: -2, capped_contribution: -1, reason: 'disabled')
    config[:preseason][:departures][:weight] = 0.5
    expect(score[:contribution]).to eq(-0.5)
  end

  it 'tunes slope and ceiling with config only and replays an old frozen report' do
    departure(60, 800)
    old = score
    config[:preseason][:departures].merge!(slope: 3, max_net_efficiency: 0.5)
    config[:bundle_name] = 'reviewed-tuning'
    expect(score[:contribution]).to eq(-0.5)
    expect(described_class.new(old[:inputs], old[:configuration]).call).to eq(old)
    expect(old[:inputs]).to be_frozen
    expect(old[:configuration]).to be_frozen
  end

  it 'rejects duplicate selection/player contributions, inconsistent denominators and excessive totals' do
    departure(1, 500)
    departure(60, 300)
    evidence[:selections].last[:stints][0][:team_points] = 3000
    expect { score }.to raise_error(ArgumentError, /denominators/)
    evidence[:selections].last[:stints][0][:team_points] = 2000
    evidence[:selections].last[:stints][0][:player_source_url] = 'https://school.example/player/1'
    expect { score }.to raise_error(ArgumentError, /Duplicate/)
    evidence[:selections].last[:stints][0][:player_source_url] = 'https://school.example/player/60'
    evidence[:selections].last[:stints][0][:player_points] = 1800
    expect { score }.to raise_error(ArgumentError, /exceed/)
    evidence[:selections] << evidence[:selections].last
    expect { score }.to raise_error(ArgumentError, /Duplicate/)
  end

  [-1, Float::NAN, Float::INFINITY, '500', true].each do |points|
    it "rejects invalid production #{points.inspect} even when disabled" do
      departure(60, points)
      config[:preseason][:departures][:weight] = 0
      expect { score }.to raise_error(ArgumentError)
    end
  end

  it 'rejects incomplete prior core numeric values, incorrect years, scope, units and unapproved evidence' do
    inputs[:previous_values][:adj_offensive_efficiency] = Float::INFINITY
    expect { score }.to raise_error(ArgumentError, /finite/)
    inputs[:previous_values][:adj_offensive_efficiency] = 100
    inputs[:target_year] = 2027
    expect { score }.to raise_error(ArgumentError, /year/)
    inputs[:target_year] = 2026
    departure(60, 500)
    evidence[:selections].last[:stints][0][:scope] = 'conference_only'
    expect { score }.to raise_error(ArgumentError, /scope/)
    evidence[:selections].last[:stints][0][:scope] = Departures::Contract::SCOPE
    evidence[:selections].last[:stints][0][:units] = {}
    expect { score }.to raise_error(ArgumentError, /units/)
    evidence[:review][:decision] = 'pending'
    expect { score }.to raise_error(ArgumentError, /approved/)
  end

  it 'rejects malformed selected/stint/candidate identities instead of silently producing verified zero' do
    [nil, '1', 0, -1].each do |id|
      captured = inputs.deep_dup.merge(team_id: id)
      expect { described_class.new(captured, config).call }.to raise_error(ArgumentError, /team_id/)
    end
    departure(60, 500)
    evidence[:selections].last[:stints][0][:team_id] = '1'
    expect { score }.to raise_error(ArgumentError, /team_id/)
    evidence[:selections].last[:stints][0][:team_id] = 1
    evidence[:selections][0].merge!(status: 'unknown_production', candidate_team_ids: ['1'])
    expect { score }.to raise_error(ArgumentError, /team_id/)
    inputs[:reviewed_departures] = nil
    inputs[:target_year] = nil
    expect { score }.to raise_error(ArgumentError, /target_year/)
  end

  it 'rejects a repeated player URL across source IDs and teams' do
    departure(1, 500)
    departure(60, 300)
    evidence[:selections].last[:stints][0].merge!(source_id: 'another-school', team_id: 2,
                                                  player_source_url: 'https://school.example/player/1')
    expect { score }.to raise_error(ArgumentError, /Duplicate player contributions/)
  end

  it 'rejects each nonzero legacy component before its aggregate cap even if components cancel' do
    inputs[:profile_values] = { recruiting_score: 10, manual_adjustment: -1 }
    expect { score }.to raise_error(ArgumentError, /overlap/)
    inputs[:profile_values] = { returning_minutes_pct: 0.5 }
    expect { score }.to raise_error(ArgumentError, /overlap/)
    config[:preseason][:departures][:weight] = 0
    config[:preseason][:recruiting] = YAML.load_file(Rails.root.join('config/examples/recruiting_r3.yml')).symbolize_keys
    expect { score }.to raise_error(ArgumentError, /overlap/)
    config[:preseason][:recruiting][:weight] = 0
    expect(score[:contribution]).to eq(0)
  end
end
