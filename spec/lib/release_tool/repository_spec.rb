# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib/release_tool/repository')

RSpec.describe ReleaseTool::Repository do
  let(:sandbox) { Dir.mktmpdir('release-git-spec-') }
  let(:remote) { File.join(sandbox, 'origin.git') }
  let(:checkout) { File.join(sandbox, 'checkout') }
  let(:tag) { 'v2026.10.16' }
  let(:plan) { { version: tag, target: git('rev-parse', 'HEAD').strip, previous_tag: nil, update: false } }

  around do |example|
    ReleaseTool.capture('git', 'init', '--bare', remote)
    ReleaseTool.capture('git', 'init', checkout)
    Dir.chdir(checkout) do
      git('config', 'user.name', 'Release Spec')
      git('config', 'user.email', 'release-spec@example.invalid')
      git('config', 'commit.gpgSign', 'false')
      git('config', 'tag.gpgSign', 'false')
      git('checkout', '-b', 'development')
      git('commit', '--allow-empty', '-m', 'Baseline')
      git('branch', 'main')
      git('commit', '--allow-empty', '-m', 'Candidate')
      git('remote', 'add', 'origin', remote)
      git('push', 'origin', 'main', 'development')
      example.run
    end
  ensure
    FileUtils.remove_entry(sandbox)
  end

  def git(*)
    ReleaseTool.capture('git', *)
  end

  it 'fetches both branches and enumerates direct commits without changing the checkout' do
    described_class.fetch
    before = git('rev-parse', 'HEAD')
    commits = described_class.commits(described_class.sha('main'), described_class.sha('development'))
    expect(commits.map(&:last)).to eq(['Candidate'])
    expect(git('rev-parse', 'HEAD')).to eq(before)
  end

  it 'pushes an annotated tag at the pinned commit with an absent-ref lease' do
    expect(described_class.validate_tag(plan)).to be_nil
    described_class.push_tag(plan)
    expect(git('cat-file', '-t', "refs/tags/#{tag}").strip).to eq('tag')
    expect(git('rev-parse', "#{tag}^{commit}").strip).to eq(plan.fetch(:target))
    expect(described_class.remote_tags.fetch(tag)).to eq(git('rev-parse', tag).strip)
  end

  it 'updates a draft tag using the exact previously observed remote object' do
    described_class.push_tag(plan)
    original = described_class.validate_tag(plan)
    git('commit', '--allow-empty', '-m', 'Additional candidate')
    update = plan.merge(update: true, previous_tag: original, target: git('rev-parse', 'HEAD').strip)
    described_class.push_tag(update)
    expect(git('rev-parse', "#{tag}^{commit}").strip).to eq(update.fetch(:target))
    expect(described_class.remote_tags.fetch(tag)).not_to eq(original)
  end

  it 'refuses to overwrite a tag changed remotely after the plan was prepared' do
    described_class.push_tag(plan)
    original = described_class.validate_tag(plan)
    baseline = described_class.sha('main')
    git('--git-dir', remote, 'update-ref', "refs/tags/#{tag}", baseline)
    expect { described_class.push_tag(plan.merge(update: true, previous_tag: original)) }
      .to raise_error(ReleaseTool::Error, /Draft.*retained/m)
    expect(described_class.remote_tags.fetch(tag)).to eq(baseline)
  end

  it 'protects an unrelated local tag rather than force-moving it during an update' do
    git('tag', '-a', tag, described_class.sha('main'), '-m', 'Local unrelated tag')
    expect { described_class.validate_tag(plan) }.to raise_error(ReleaseTool::Error, /Local tag.*differs/)
    expect(described_class.remote_tags).to be_empty
  end
end
