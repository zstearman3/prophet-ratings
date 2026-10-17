# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/release_tool/draft')

RSpec.describe ReleaseTool::Draft do
  let(:repository) { object_double(ReleaseTool::Repository, fetch: nil, tags: [], validate_tag: nil, push_tag: nil) }
  let(:options) { { dry_run: false, update: false, date: Date.new(2026, 10, 16) } }
  let(:commands) { [] }
  let(:saved_notes) { [] }
  let(:draft) { described_class.new(options, repository:) }

  before do
    allow(repository).to receive(:sha).with('development').and_return('a' * 40)
    allow(repository).to receive(:sha).with('main').and_return('b' * 40)
    allow(repository).to receive(:commits).and_return([['a' * 40, 'Direct fix']])
    allow(ReleaseTool).to receive(:json).with('gh', 'repo', 'view', '--json', 'nameWithOwner').and_return('nameWithOwner' => 'owner/repo')
    allow(ReleaseTool).to receive(:capture) do |*args|
      commands << args
      saved_notes << File.read(args.last) if args.include?('--notes-file')
      ''
    end
  end

  it 'creates a draft pinned to development before pushing its tag and passes notes through a file' do
    expect { draft.call }.to output(/Draft v2026.10.16 prepared/).to_stdout
    creation = commands.find { |args| args[0, 3] == %w[gh release create] }
    expect(creation).to include('--draft', '--target', 'a' * 40, '--notes-file')
    expect(saved_notes.first).to include('Direct fix', 'Production baseline:')
    expect(repository).to have_received(:push_tag).with(hash_including(target: 'a' * 40, version: 'v2026.10.16', update: false))
  end

  it 'makes dry-run read-only even though it fetches the latest refs and builds notes' do
    options[:dry_run] = true
    expect { draft.call }.to output(/Dry run: no tags or releases changed/).to_stdout
    expect(repository).not_to have_received(:push_tag)
    expect(commands.none? { |args| args[0, 2] == %w[gh release] }).to be(true)
  end

  it 'refuses updates to published releases, including in dry-run' do
    options.merge!(update: true, tag: 'v2026.10.15', dry_run: true)
    allow(ReleaseTool).to receive(:json).with('gh', 'release', 'view', 'v2026.10.15', '--repo', 'owner/repo', '--json', 'isDraft')
                                        .and_return('isDraft' => false)
    expect { draft.call }.to raise_error(ReleaseTool::Error, /already published/)
    expect(repository).not_to have_received(:push_tag)
    expect(saved_notes).to be_empty
  end

  it 'updates only an existing draft and keeps its original remote tag lease' do
    options.merge!(update: true, tag: 'v2026.10.15')
    allow(repository).to receive(:validate_tag).and_return('old-tag-object')
    allow(ReleaseTool).to receive(:json).with('gh', 'release', 'view', 'v2026.10.15', '--repo', 'owner/repo', '--json', 'isDraft')
                                        .and_return('isDraft' => true)
    expect { draft.call }.to output(/Draft v2026.10.15 prepared/).to_stdout
    expect(commands.find { |args| args[0, 3] == %w[gh release edit] }).not_to include('--draft')
    expect(repository).to have_received(:push_tag).with(hash_including(previous_tag: 'old-tag-object', update: true))
  end

  it 'does not create or push a tag if GitHub draft creation fails' do
    allow(ReleaseTool).to receive(:capture).with('gh', 'release', 'create', any_args).and_raise(ReleaseTool::Error, 'GitHub unavailable')
    expect { expect { draft.call }.to raise_error(ReleaseTool::Error, /GitHub unavailable/) }.to output(/Release v2026/).to_stdout
    expect(repository).not_to have_received(:push_tag)
  end

  it 'stops before writes when no commits are ahead of production' do
    allow(repository).to receive(:commits).and_return([])
    expect { draft.call }.to raise_error(ReleaseTool::Error, /No commits/)
    expect(saved_notes).to be_empty
    expect(repository).not_to have_received(:push_tag)
  end
end
