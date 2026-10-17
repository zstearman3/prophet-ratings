# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/release_tool/notes')

RSpec.describe ReleaseTool::Notes do
  let(:notion) { instance_double(ReleaseTool::Notion, tickets: []) }
  let(:builder) { described_class.new('owner/repo', notion:) }
  let(:sha) { 'a' * 40 }
  let(:pull_request) do
    { 'number' => 185, 'title' => 'Review evidence', 'body' => 'Ticket link', 'url' => 'https://github.com/owner/repo/pull/185',
      'state' => 'MERGED', 'mergeCommit' => { 'oid' => sha }, 'author' => { 'login' => 'maintainer' } }
  end
  let(:plan) { { version: 'v2026.10.16', base: 'b' * 40, target: sha, commits: [[sha, 'Review evidence (#185)']] } }

  before { allow(ReleaseTool).to receive(:json).and_return(pull_request) }

  it 'groups linked PRs by current Notion status and retains the PR and task links' do
    allow(notion).to receive(:tickets).and_return([{ title: 'Offseason review', status: 'Testing', url: 'https://www.notion.so/task' }])
    notes = builder.render(plan)
    expect(notes).to include('## Testing', '[Review evidence (#185)](https://github.com/owner/repo/pull/185)',
                             '[Offseason review](https://www.notion.so/task)', "Candidate: `#{sha}`")
  end

  it 'includes unlinked PRs and direct commits instead of silently omitting them' do
    plan[:commits] << ['c' * 40, 'Direct operational fix']
    expect(builder.render(plan)).to include('## No Notion ticket', 'Review evidence', '## Other commits', 'Direct operational fix')
  end

  it 'separates Dependabot by author without relying on a title pattern' do
    pull_request['author']['login'] = 'app/dependabot'
    expect(builder.render(plan)).to include('## Dependabot updates')
    expect(notion).not_to have_received(:tickets)
  end

  it 'treats an incidental PR-number suffix as a direct commit if the merge SHA does not match' do
    pull_request['mergeCommit']['oid'] = 'd' * 40
    expect(builder.render(plan)).to include('## Other commits')
  end

  it 'handles traditional merge subjects and escapes Markdown/newlines in titles' do
    plan[:commits] = [[sha, 'Merge pull request #185 from owner/feature']]
    pull_request['title'] = "A [title]\nwith *formatting*"
    expect(builder.render(plan)).to include('A \\[title\\] with \\*formatting\\*')
  end
end
