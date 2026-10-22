# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe Departures::FileCheckpoint do
  let(:directory) { Dir.mktmpdir('checkpoint') }
  let(:path) { File.join(directory, 'manifest.partial.json') }
  let(:original) { { 'captures' => [{ 'id' => 'capture-1', 'snapshot_sha256' => Digest::SHA256.hexdigest('original raw body') }] } }
  let(:replacement) { { 'captures' => original.fetch('captures') + [{ 'id' => 'capture-2' }] } }

  before { File.binwrite(File.join(directory, 'source.json'), 'original raw body') }
  after { FileUtils.remove_entry(directory) }

  it 'replaces a complete checkpoint privately while leaving retained bodies unchanged' do
    checkpoint = described_class.new(path)
    checkpoint.call(original)
    checkpoint.call(replacement)
    expect(JSON.parse(File.read(path))).to eq(replacement)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(Dir.children(directory)).to contain_exactly('manifest.partial.json', 'source.json')
  end

  [IOError, Interrupt].each do |failure|
    it "preserves the preceding valid ledger and removes partial temporary output after #{failure}" do
      checkpoint = described_class.new(path)
      checkpoint.call(original)
      allow(Tempfile).to receive(:create).and_wrap_original do |create, *arguments, &operation|
        create.call(*arguments) do |file|
          write = file.method(:write)
          allow(file).to receive(:write) do |bytes|
            write.call(bytes[0, bytes.size / 2])
            raise failure, 'Synthetic interrupted replacement'
          end
          operation.call(file)
        end
      end
      expect { checkpoint.call(replacement) }.to raise_error(failure)
      expect(JSON.parse(File.read(path))).to eq(original)
      bytes = File.binread(File.join(directory, 'source.json'))
      expect(Digest::SHA256.hexdigest(bytes)).to eq(original.dig('captures', 0, 'snapshot_sha256'))
      expect(Dir.children(directory)).to contain_exactly('manifest.partial.json', 'source.json')
    end
  end
end
