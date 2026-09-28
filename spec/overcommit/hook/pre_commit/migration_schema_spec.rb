# frozen_string_literal: true

require 'rails_helper'
require 'overcommit'
require 'overcommit/hook/pre_commit/base'
require Rails.root.join('.git-hooks/pre_commit/migration_schema')

RSpec.describe Overcommit::Hook::PreCommit::MigrationSchema do
  subject(:result) { described_class.new(configuration, context).run }

  let(:configuration) { instance_double(Overcommit::Configuration, for_hook: {}) }
  let(:context) { instance_double(Overcommit::HookContext::Base, all_files: files, modified_files: staged) }
  let(:schema) { Rails.root.join('db/schema.rb').to_s }
  let(:migration) { Rails.root.join('db/migrate/20260928000000_add_example.rb').to_s }
  let(:files) { [schema, migration] }
  let(:staged) { [schema, migration] }
  let(:schema_contents) { 'ActiveRecord::Schema[8.1].define(version: 2026_09_28_000000) do' }

  before do
    allow(File).to receive(:read).with(schema).and_return(schema_contents)
  end

  it 'accepts a migration and matching staged schema without a database' do
    expect(result).to eq(:pass)
  end

  context 'when the schema is not staged' do
    let(:staged) { [migration] }

    it 'fails even if the working schema already has the right version' do
      expect(result).to eq([:fail, 'Migration changes need a staged db/schema.rb update. ' \
                                   'Run bin/migrate, then review and stage db/schema.rb with your migrations.'])
    end
  end

  context 'when the schema version is stale' do
    let(:schema_contents) { 'ActiveRecord::Schema[8.1].define(version: 2026_06_22_000100) do' }

    it 'fails even when both files are staged' do
      expect(result.first).to eq(:fail)
      expect(result.last).to include('20260928000000', 'bin/migrate')
    end
  end

  context 'when the schema only changes format' do
    let(:staged) { [schema] }

    it 'allows a schema-only refresh at the current version' do
      expect(result).to eq(:pass)
    end
  end

  context 'when an older migration is staged' do
    let(:older_migration) { Rails.root.join('db/migrate/20260927000000_add_other.rb').to_s }
    let(:files) { [schema, older_migration, migration] }
    let(:staged) { [schema, older_migration] }

    it 'compares the schema with all tracked migrations, not just staged ones' do
      expect(result).to eq(:pass)
    end
  end

  context 'when the schema is from a newer branch' do
    let(:schema_contents) { 'ActiveRecord::Schema[8.1].define(version: 2026_09_29_000000) do' }

    it 'rejects a schema ahead of this branch' do
      expect(result.first).to eq(:fail)
    end
  end

  context 'when the schema header is missing' do
    let(:schema_contents) { '# No schema here' }

    it 'fails instead of trusting a malformed schema' do
      expect(result.first).to eq(:fail)
    end
  end
end
