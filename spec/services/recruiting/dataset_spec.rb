# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::Dataset do
  let(:document) { JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read) }
  let(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team, school: 'Test College') }

  def bytes
    JSON.generate(document)
  end

  def dataset
    described_class.new(bytes, 'saved source evidence')
  end

  def preview
    Recruiting::Preview.new(dataset, season).call
  end

  it 'retains exact evidence and decimal points without rounding, and repeats deterministically' do
    Dir.mktmpdir do |root|
      path = dataset.save(root)
      expect(dataset.save(root)).to eq(path)
      expect(File.binread(File.join(path, 'original.json'))).to eq(bytes)
      expect(File.binread(File.join(path, 'snapshot'))).to eq('saved source evidence')
      expect(described_class.load(path).manifest.dig('rows', 0, 'values', 'class_points')).to eq('70.123456789123456789')
      first_preview = preview
      expect(preview).to eq(first_preview)
    end
  end

  it 'matches canonical schools even without aliases and writes no domain records' do
    expect { preview }.not_to(change { [Team.count, TeamOffseasonProfile.count, TeamRatingSnapshot.count, season.reload.attributes] })
    expect(preview.fetch('eligible_rows')).to eq(1)
    expect(preview.fetch('rows').first.fetch('team_id')).to eq(team.id)
  end

  it 'reuses only exact provider-scoped aliases' do
    document['rows'].first['team_label'] = 'Source Label'
    create(:team_alias, team:, source: 'sports_reference', value: 'Source Label')
    expect(preview.fetch('eligible_rows')).to eq(0)
    create(:team_alias, team:, source: '247sports', value: 'Source Label')
    expect(preview.fetch('eligible_rows')).to eq(1)
  end

  it 'reports canonical versus alias ambiguity without selecting a team' do
    other = create(:team)
    create(:team_alias, team: other, source: '247sports', value: team.school)
    row = preview.fetch('rows').first
    expect(row['team_id']).to be_nil
    expect(row['candidate_team_ids']).to eq([team.id, other.id].sort)
    expect(row['exclusions']).to include(/Ambiguous/)
  end

  it 'excludes every duplicate source identity and canonical team' do
    document['rows'] << document['rows'].first.merge('class_points' => '66')
    expect(preview.fetch('eligible_rows')).to eq(0)
    expect(preview.fetch('rows').map { |row| row['exclusions'].join }).to all(include('Duplicate'))
  end

  it 'also detects distinct labels resolving to one canonical team' do
    create(:team_alias, team:, source: '247sports', value: 'Other label')
    document['rows'] << document['rows'].first.merge('team_label' => 'Other label', 'provider_team_id' => 'another')
    expect(preview.fetch('eligible_rows')).to eq(0)
    expect(preview.fetch('rows').map { |row| row['exclusions'].join }).to all(include('team_id'))
  end

  it 'distinguishes missing points, explicit zero and omitted teams' do
    other = create(:team)
    document['rows'].first.delete('class_points')
    expect(preview.fetch('missing_points_rows')).to eq([1])
    expect(preview.fetch('omitted_stored_team_ids')).to include(other.id)
    document['rows'].first['class_points'] = 0
    expect(preview.fetch('explicit_zero_rows')).to eq([1])
    expect(preview.fetch('missing_points_rows')).to be_empty
  end

  it 'keeps valid empty source coverage distinct from failures' do
    document['rows'] = []
    expect(preview).to include('coverage' => 'empty', 'source_status' => 'ok', 'eligible_rows' => 0)
  end

  %w[NaN Infinity -1 bad].each do |value|
    it "excludes invalid class points #{value}" do
      document['rows'].first['class_points'] = value
      expect(preview.fetch('eligible_rows')).to eq(0)
      expect(preview.fetch('rows').first.fetch('exclusions')).to include(/class_points/)
    end
  end

  it 'reports malformed rows and noninteger counts' do
    document['rows'] << 'malformed'
    document['rows'].first['commit_count'] = 1.5
    expect(preview.fetch('eligible_rows')).to eq(0)
    expect(preview.fetch('rows').last.fetch('exclusions')).to include('Expected row object')
  end

  [{ 'unexpected' => 'object' }, ['Test College'], 123].each do |label|
    it "keeps malformed identity #{label.inspect} out of database matching" do
      document['rows'] << document['rows'].first.merge('team_label' => label, 'provider_team_id' => 'malformed')
      expect(preview.fetch('eligible_rows')).to eq(1)
      expect(preview.fetch('rows').last).to include('candidate_team_ids' => [], 'team_id' => nil)
    end
  end

  %w[transfer overall].each do |category|
    it "rejects #{category} category" do
      document['category'] = category
      expect { dataset }.to raise_error(ArgumentError, /Only 247sports/)
    end
  end

  it 'rejects wrong year mapping and a mismatched preview season' do
    document['target_season'] = 2026
    expect { dataset }.to raise_error(ArgumentError, /Y\+1/)
    document['target_season'] = 2027
    expect { Recruiting::Preview.new(dataset, create(:season, year: 2028)).call }.to raise_error(ArgumentError, /target season/)
  end

  %w[access_failure network_failure parse_failure].each do |status|
    it "rejects #{status} without treating it as empty coverage" do
      document['source_status'] = status
      document['rows'] = []
      expect { dataset }.to raise_error(ArgumentError, /Source failure/)
    end
  end

  it 'rejects malformed JSON and invalid UTF-8' do
    expect { described_class.new('{bad', '') }.to raise_error(JSON::ParserError)
    expect { described_class.new("\xFF", '') }.to raise_error(ArgumentError, /UTF-8/)
  end

  it 'requires explicit provenance and timezone, including a reason for unavailable source date' do
    document['source_as_of_reason'] = nil
    expect { dataset }.to raise_error(ArgumentError, /reason/)
    document['source_as_of_reason'] = 'Not displayed'
    document['captured_at'] = '2026-10-10'
    expect { dataset }.to raise_error(ArgumentError, /timezone/)
  end

  it 'rejects modified saved evidence and refuses to overwrite the bundle' do
    Dir.mktmpdir do |root|
      path = dataset.save(root)
      File.write(File.join(path, 'snapshot'), 'changed')
      expect { described_class.load(path) }.to raise_error(ArgumentError, /integrity/)
      expect { dataset.save(root) }.to raise_error(ArgumentError, /integrity/)
    end
  end

  it 'saves approval separately and rejects stale alias mappings' do
    report = preview
    approval = report.slice('dataset_revision', 'mapping_revision').merge('approved_by' => 'Test reviewer',
                                                                          'approved_at' => '2026-10-10T20:00:00Z')
    Dir.mktmpdir do |root|
      review = Recruiting::MappingReview.new(report)
      path = review.save(root, approval)
      expect(review.save(root, approval)).to eq(path)
      expect(JSON.parse(File.read(path))).to include('review_status' => 'reviewed',
                                                     'approval' => approval.slice(
                                                       'approved_by', 'approved_at'
                                                     ))
      other = create(:team)
      create(:team_alias, team: other, source: '247sports', value: team.school)
      expect { Recruiting::MappingReview.new(preview).approve(approval) }.to raise_error(ArgumentError, /pin/)
    end
  end
end
