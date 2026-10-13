# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Departures::AnnualDataset do
  let(:directory) { Dir.mktmpdir('departures') }
  let(:fixture_root) { Rails.root.join('spec/fixtures/departures') }
  let(:draft_source) { { 'id' => 'draft', 'type' => 'nba_results', 'url' => 'https://www.nba.com/news/2025-nba-draft-order' } }
  let(:school_source) do
    { 'id' => 'school', 'type' => 'sidearm_totals', 'url' => 'https://school.example/sports/mens-basketball/stats/2024-25',
      'team_name_source' => 'Sample School', 'scope' => Departures::Contract::SCOPE,
      'scope_evidence' => 'Operator verified completed overall season including postseason, no exhibitions' }
  end
  let(:settings) { { 'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => (1..60).to_a } }
  let(:manifest) { settings.merge('sources' => [saved(draft_source, 'draft.html'), saved(school_source, 'school.html')]) }
  let(:dataset) { described_class.new(manifest:, directory:).call }

  after { FileUtils.remove_entry(directory) }

  def saved(source, fixture)
    html = File.binread(fixture_root.join(fixture))
    allow(HTTParty).to receive(:get).with(source.fetch('url'), timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, body: html, code: 200))
    Departures::SourceCapture.new(directory:).call(source)
  end

  it 'extracts high and late picks and original totals with the full denominator' do
    expect(dataset.fetch('selections').pluck('overall_pick')).to eq((1..60).to_a)
    totals = dataset.fetch('production').first
    expect(totals.slice('team_points', 'team_minutes')).to eq('team_points' => 2000, 'team_minutes' => 6400)
    expect(totals.fetch('players').pluck('player_points')).to eq([500, 0, 1500])
    expect(dataset.fetch('failures')).to be_empty
  end

  it 'replays saved bytes deterministically without network access or changed capture hashes' do
    original = dataset
    allow(HTTParty).to receive(:get).and_raise('No network during replay')
    expect(described_class.new(manifest:, directory:).call).to eq(original)
    expect(original.fetch('dataset_revision')).to eq(Departures::Contract.digest(original.except('dataset_revision')))
  end

  it 'retains blocked response bytes and reports partial acquisition' do
    allow(HTTParty).to receive(:get).with(draft_source.fetch('url'), timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, body: 'Access denied', code: 403))
    blocked = Departures::SourceCapture.new(directory:).call(draft_source)
    partial = described_class.new(manifest: settings.merge('sources' => [blocked]), directory:).call
    expect(partial.fetch('selections')).to be_empty
    expect(partial.fetch('failures').first.fetch('failure')).to include('HTTP 403')
    expect(File.binread(File.join(directory, blocked.fetch('snapshot_location')))).to eq('Access denied')
  end

  it 'reports a network failure without pretending to have a snapshot' do
    allow(HTTParty).to receive(:get).and_raise(SocketError)
    failed = Departures::SourceCapture.new(directory:).call(draft_source)
    expect(failed.fetch('failure')).to include('SocketError')
    expect(failed).not_to have_key('snapshot_sha256')
  end

  it 'reports tampered source bytes while preserving other source results' do
    source = manifest.fetch('sources').last
    File.write(File.join(directory, source.fetch('snapshot_location')), 'changed')
    expect(dataset.fetch('failures').first.fetch('failure')).to eq('Source snapshot hash mismatch')
    expect(dataset.fetch('selections').size).to eq(60)
  end

  it 'refuses an incompatible season mapping' do
    expect { described_class.new(manifest: manifest.merge('prior_season_year' => 2024), directory:) }
      .to raise_error(ArgumentError, /requires prior_season_year/)
  end

  %w[prior_season_year target_year].each do |key|
    it "rejects fractional #{key} rather than accepting numeric equality" do
      invalid = settings.merge(key => settings.fetch(key).to_f)
      expect { Departures::Contract.years!(invalid) }.to raise_error(ArgumentError, /expected integer/)
    end
  end

  it 'reports a truncated NBA page instead of accepting partial selections' do
    html = File.read(fixture_root.join('draft.html')).sub(%r{<p>59\..*?</p>}, '')
    expect { Departures::NbaResults.new(source: draft_source, html:, draft_year: 2025).call }
      .to raise_error(ArgumentError, /Partial draft results/)
  end

  it 'never replaces immutable output files' do
    path = File.join(directory, 'annual.json')
    Departures::Contract.write(path, dataset)
    expect { Departures::Contract.write(path, dataset) }.not_to(change { File.mtime(path) })
    expect { Departures::Contract.write(path, {}) }.to raise_error(Errno::EEXIST)
  end

  it 'rejects early-entry pages and incorrect year results as unsupported' do
    parser = Departures::NbaResults.new(source: draft_source, html: '<h1>2025 Early Entry Candidates</h1>', draft_year: 2025)
    expect { parser.call }.to raise_error(ArgumentError, /title/)
  end

  it 'rejects duplicate selection and player identities' do
    html = File.read(fixture_root.join('draft.html'))
    duplicate = html.sub('60.', '1.')
    expect { Departures::NbaResults.new(source: draft_source, html: duplicate, draft_year: 2025).call }
      .to raise_error(ArgumentError, %r{pick/round})
    duplicate = html.sub('blair-beta', 'alex-alpha')
    expect { Departures::NbaResults.new(source: draft_source, html: duplicate, draft_year: 2025).call }
      .to raise_error(ArgumentError, /Duplicate draft player/)
  end

  [['wrong season', '2024-25', '2023-24'], ['per-game column', '>PTS<', '>AVG<'],
   ['zero denominator', '>2,000<', '>0<'], ['negative points', '>500<', '>-500<'], ['fractional games', '>30<', '>30.5<'],
   ['nonfinite minutes', '>800<', '>NaN<'], ['conflicting denominator', '>2,000<', '>2,100<'],
   ['wrong scope', 'Overall Totals', 'Conference Totals']].each do |description, original, replacement|
    it "reports unsupported/invalid school totals: #{description}" do
      html = File.read(fixture_root.join('school.html')).sub(original, replacement)
      parser = Departures::SidearmTotals.new(source: school_source, html:, prior_season_year: 2025)
      expect { parser.call }.to raise_error(ArgumentError)
    end
  end
end
