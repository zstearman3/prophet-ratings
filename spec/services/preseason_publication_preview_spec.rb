# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PreseasonPublicationPreview do
  let(:season) { create(:season, average_pace: nil, average_efficiency: nil) }
  let(:version) { RatingsConfigVersion.publish! }
  let!(:first) { create(:team_season, season:) }
  let!(:second) { create(:team_season, season:) }

  it 'reports synthetic fallback values and deterministic ranks without rating writes' do
    report = described_class.new(season, ratings_config_version: version, mode: 'initialize').call
    expect(report['teams'].map { |row| row['after'].values_at('offense', 'defense', 'pace', 'net', 'rank') })
      .to eq([[105.5, 105.5, 69.5, 0.0, 1], [105.5, 105.5, 69.5, 0.0, 2]])
    expect(report['teams'].pluck('team_id')).to eq([first.team_id, second.team_id])
    expect(report['gaps'].size).to eq(4)
    expect([PreseasonPrior.count, TeamRatingSnapshot.count, first.reload.adj_pace]).to eq([0, 0, nil])
  end

  it 'projects saved presentation without replay operands while preserving provenance and values' do
    report = described_class.new(season, ratings_config_version: version, mode: 'initialize').call
    row = report['teams'].first
    row['inputs']['reviewed_departures'] = { 'revision' => { 'id' => 17, 'input_hash' => 'a' * 64 },
                                             'review' => { 'decision' => 'approved', 'decisions' => ['all-team decisions'] },
                                             'sources' => [{ 'rows' => ['raw body'] }] }
    presented = described_class.presentation(report)
    expect(presented.slice('fingerprint', 'coverage', 'gaps')).to eq(report.slice('fingerprint', 'coverage', 'gaps'))
    expect(presented['teams'].first.slice('before', 'after', 'efficiency')).to eq(row.slice('before', 'after', 'efficiency'))
    expect(presented['teams'].first.dig('inputs', 'reviewed_departures')).to eq(
      'revision' => { 'id' => 17, 'input_hash' => 'a' * 64 }, 'review' => { 'decision' => 'approved' }
    )
    expect(presented['teams'].first.dig('inputs', 'baselines')).to eq(row.dig('inputs', 'baselines'))
    expect(row.dig('inputs', 'reviewed_departures', 'sources')).to be_present
  end

  it 'rejects an empty included roster without creating outputs' do
    empty = create(:season, year: 2029)
    expect { described_class.new(empty, ratings_config_version: version, mode: 'initialize').call }
      .to raise_error(ArgumentError, /No included teams/)
    expect([PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([0, 0])
  end

  it 'retains recruiting revision provenance and distinguishes verified zero from missing departures' do
    config = RatingsConfigVersion.authored_config.merge(bundle_name: 'publication-reviewed')
    config[:preseason].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')).deep_symbolize_keys)
    reviewed_model = RatingsConfigVersion.publish!(config)
    approval = { 'review_status' => 'reviewed',
                 'approval' => { 'approved_by' => 'Synthetic operator', 'approved_at' => Time.current.iso8601 } }
    recruiting = { 'status' => 'verified_zero', 'class_points' => '0',
                   'units' => { 'class_points' => '247_recruit_composite_class_points' } }
    payload = { 'kind' => 'recruiting', 'dataset_hash' => 'a' * 64, 'review_hash' => Departures::Contract.digest(approval),
                'review' => approval, 'team_inputs' => { first.team_id.to_s => recruiting } }
    revision = OffseasonInputRevision.create!(season:, kind: 'recruiting', version: 'publication-zero', reason: 'Synthetic review',
                                              input_hash: Departures::Contract.digest(payload), dataset_hash: payload['dataset_hash'],
                                              review_hash: payload['review_hash'], payload:)
    create(:team_offseason_profile, team_season: first, recruiting_revision: revision,
                                    recruiting_score: nil, returning_minutes_pct: nil, manual_adjustment: nil)
    report = described_class.new(season, ratings_config_version: reviewed_model, mode: 'initialize').call
    entry = report['teams'].first
    expect(entry.dig('inputs', 'reviewed_recruiting', 'revision', 'id')).to eq(revision.id)
    expect(entry.dig('efficiency', 'recruiting', 'class_points')).to eq(0.0)
    expect(report['gaps'].select { |gap| gap['team_id'] == first.team_id }.pluck('kind')).to eq(['departures'])
    expect(entry.dig('inputs', 'reviewed_recruiting', 'review', 'approval', 'approved_by')).to eq('Synthetic operator')
  end
end
