# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::Cbbd::MembershipDirectory do
  let(:document) do
    { 'season' => 2027, 'teams' => [{ 'id' => '001', 'school' => 'Synthetic U', 'conferenceId' => 10 }],
      'conferences' => [{ 'id' => 10, 'name' => 'Synthetic Conference', 'abbreviation' => 'SC' }] }
  end

  def normalize
    described_class.normalize(document, 2027)
  end

  it 'preserves opaque IDs and joins season affiliations from the object envelope' do
    expect(normalize.sole).to include(team_external_id: '001', conference_external_id: '10', team_name: 'Synthetic U')
  end

  [2026, '2027', nil].each do |year|
    it "rejects an invalid echoed year #{year.inspect}" do
      document['season'] = year
      expect { normalize }.to raise_error(ArgumentError, /echo/)
    end
  end

  %w[teams conferences].each do |collection|
    it "rejects empty #{collection} coverage" do
      document[collection] = []
      expect { normalize }.to raise_error(ArgumentError, /coverage/)
    end

    it "rejects duplicate #{collection} IDs" do
      document[collection] *= 2
      expect { normalize }.to raise_error(ArgumentError, /duplicate/)
    end
  end

  [nil, '', ' ', 0, -1, 1.5].each do |id|
    it "rejects malformed stable ID #{id.inspect}" do
      document['teams'].first['id'] = id
      expect { normalize }.to raise_error(ArgumentError, /stable IDs/)
    end
  end

  it 'rejects missing conference metadata rather than inferring independence' do
    document['teams'].first['conferenceId'] = 99
    expect { normalize }.to raise_error(ArgumentError, /missing conference metadata/)
  end

  it 'validates unreferenced conference metadata too' do
    document['conferences'] << { 'id' => '20' }
    expect { normalize }.to raise_error(ArgumentError, /labels/)
  end

  it 'normalizes positive integral numeric IDs without altering leading-zero strings' do
    document['teams'].first['conferenceId'] = 10.0
    document['conferences'].first['id'] = 10.0
    expect(normalize.sole).to include(team_external_id: '001', conference_external_id: '10')
  end

  it 'rejects missing school labels' do
    document['teams'].first.delete('school')
    expect { normalize }.to raise_error(ArgumentError, /labels/)
  end

  it 'requests only the selected season and retains private sanitized capture provenance' do
    Dir.mktmpdir do |directory|
      requests = []
      transport = lambda do |uri, _key|
        requests << uri.path
        expect(uri.request_uri).to eq('/teams/directory?season=2027')
        { status: 200, body: document.merge('debug' => 'private-key').to_json }
      end
      result = described_class.new(source_year: 2027, api_key: 'private-key', capture_directory: directory,
                                   max_requests: 1, retries: 0, transport:).call
      expect(requests).to eq(['/teams/directory'])
      capture = result.dig('acquisition', 'captures').sole
      bytes = File.read(File.join(directory, capture.fetch('body_file')))
      expect(bytes).to include('[REDACTED]')
      expect(File.stat(directory).mode & 0o777).to eq(0o700)
      expect(File.stat(File.join(directory, capture.fetch('body_file'))).mode & 0o777).to eq(0o600)
    end
  end

  it 'enforces the total retry request budget with visible failure' do
    Dir.mktmpdir do |directory|
      transport = ->(_uri, _key) { { status: 429, body: 'quota' } }
      service = described_class.new(source_year: 2027, api_key: 'key', capture_directory: directory,
                                    max_requests: 1, retries: 2, transport:, sleeper: ->(_seconds) {})
      expect { service.call }.to raise_error(ArgumentError, /request_budget/)
      expect(Dir.glob(File.join(directory, '*.body')).size).to eq(1)
    end
  end

  %w[/games /games/teams].each do |endpoint|
    it "still rejects object envelopes for #{endpoint}" do
      result = Ingestion::Cbbd::Response.new({ status: 200, body: document.to_json }, 'key', endpoint:).outcome
      expect(result['outcome']).to eq('malformed_envelope')
    end
  end

  it 'rejects array envelopes for the directory' do
    result = Ingestion::Cbbd::Response.new({ status: 200, body: '[]' }, 'key', endpoint: '/teams/directory').outcome
    expect(result['outcome']).to eq('malformed_envelope')
  end
end
