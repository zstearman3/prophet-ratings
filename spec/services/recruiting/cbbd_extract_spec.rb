# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::CbbdExtract do
  let(:body) { Rails.root.join('spec/fixtures/recruiting/cbbd-2025.json').read }

  it 'normalizes genuine retained class 2025 points and preserves exact numeric JSON precision' do
    rows = described_class.normalize(body, 2025)
    expect(rows.first).to include('provider_team_id' => '72', 'team_label' => 'Duke', 'rank' => 1,
                                  'class_points' => '70.04', 'average_rating' => nil, 'commit_count' => nil)
    html = Rails.root.join('spec/fixtures/recruiting/247-2025-parity-excerpt.html').read
    historical = Recruiting::HtmlPage.new(html, Recruiting::HtmlPage.source_url(2025), 2025).rows
    expect(rows.first(8).map { |row| row.slice('team_label', 'rank', 'class_points').transform_values(&:to_s) })
      .to eq(historical.map { |row| row.slice('team_label', 'rank', 'class_points') })
    precise = body.sub('70.04', '70.123456789123456789')
    expect(described_class.normalize(precise, 2025).first['class_points']).to eq('70.123456789123456789')
  end

  it 'distinguishes empty success, zero and missing from invalid typed source data' do
    expect(described_class.normalize('[]', 2025)).to eq([])
    source = JSON.parse(body).first
    [0, nil].each do |points|
      expect(described_class.normalize(JSON.generate([source.merge('rating' => points)]), 2025).first['class_points'])
        .to eq(points.nil? ? nil : '0.0')
    end
    [{ 'teamId' => '72' }, { 'teamId' => 0 }, { 'year' => 2026 }, { 'year' => 2025.0 }, { 'rating' => '70.04' }, { 'rating' => -1 },
     { 'ranking' => 0 }, { 'team' => nil }].each do |invalid|
      expect { described_class.normalize(JSON.generate([source.merge(invalid)]), 2025) }.to raise_error(ArgumentError)
    end
    expect { described_class.normalize('{}', 2025) }.to raise_error(ArgumentError)
  end

  it 'replays normalized genuine rows from the selected retained response and rejects coordinated extract edits' do
    metadata = JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read).except('rows')
    metadata.merge!('provider' => 'cbbd', 'source_year' => 2025, 'target_season' => 2026,
                    'extraction_version' => described_class::VERSION, 'source_url' => described_class.source_url(2025),
                    'snapshot_kind' => 'raw_json_bundle', 'rows' => described_class.normalize(body, 2025))
    captured = { 'body_base64' => Base64.strict_encode64(body), 'sha256' => Digest::SHA256.hexdigest(body),
                 'metadata' => { 'outcome' => 'success', 'status' => 200,
                                 'request' => { 'endpoint' => '/recruiting/teams', 'year' => 2025 } } }
    snapshot = JSON.generate('captures' => [captured], 'selected_capture' => 0)
    dataset = Recruiting::Dataset.new(JSON.generate(metadata), snapshot)
    expect(dataset.manifest.fetch('rows').first.dig('values', 'class_points')).to eq('70.04')
    metadata['rows'].first['class_points'] = '99.0'
    expect { Recruiting::Dataset.new(JSON.generate(metadata), snapshot) }.to raise_error(ArgumentError, /retained response/)
  end
end
