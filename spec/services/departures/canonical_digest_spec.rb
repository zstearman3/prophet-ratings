# frozen_string_literal: true

require 'json'
require 'digest'
require 'tmpdir'
require_relative '../../../app/services/departures/canonical_digest'
require_relative '../../../app/services/departures/contract'

RSpec.describe Departures::CanonicalDigest do
  it 'hashes nested objects in canonical key order without changing array order or scalar types' do
    value = { 'z' => [{ 'b' => false, 'a' => nil }, 2.5], 'a' => { 'z' => 0, 'a' => 'college' } }
    canonical = '{"a":{"a":"college","z":0},"z":[{"a":null,"b":false},2.5]}'
    expect(described_class.new.call(value)).to eq(Digest::SHA256.hexdigest(canonical))
    expect(described_class.new.call(value.to_a.reverse.to_h)).to eq(Digest::SHA256.hexdigest(canonical))
  end

  it 'preserves Unicode and JSON escaping in retained source strings' do
    value = { 'source' => "Duké\n\"quoted\"\\line" }
    canonical = '{"source":"Duké\n\"quoted\"\\\\line"}'
    expect(described_class.new.call(value)).to eq(Digest::SHA256.hexdigest(canonical))
  end

  it 'preserves symbol-key and empty-container encoding' do
    value = { z: [], a: {}, n: -0.0 }
    expect(described_class.new.call(value)).to eq(Digest::SHA256.hexdigest('{"a":{},"n":-0.0,"z":[]}'))
  end

  it 'retains the JSON generator depth and nonfinite-value restrictions' do
    expect { described_class.new.call(Float::NAN) }.to raise_error(JSON::GeneratorError)
    nested = 101.times.reduce(nil) { |value, _index| [value] }
    expect { described_class.new.call(nested) }.to raise_error(JSON::NestingError)
  end

  describe 'canonical evidence files' do
    it 'preserves pretty sorted bytes, identical retries and exclusive creation' do
      value = { 'z' => [{ 'b' => 2, 'a' => 1 }], 'a' => nil }
      expected = "{\n  \"a\": null,\n  \"z\": [\n    {\n      \"a\": 1,\n      \"b\": 2\n    }\n  ]\n}\n"
      Dir.mktmpdir do |directory|
        path = File.join(directory, 'dataset.json')
        Departures::Contract.write(path, value)
        expect(File.binread(path)).to eq(expected)
        expect { Departures::Contract.write(path, value) }.not_to(change { File.mtime(path) })
        expect { Departures::Contract.write(path, { 'different' => true }) }.to raise_error(Errno::EEXIST)
        expect(File.binread(path)).to eq(expected)
      end
    end
  end
end
