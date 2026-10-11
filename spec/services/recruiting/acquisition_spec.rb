# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::Acquisition do
  let(:metadata) do
    { 'source_year' => 2026, 'target_season' => 2027, 'category' => 'recruit_composite',
      'observed_at' => '2026-10-11T00:00:00Z', 'retrieved_at' => '2026-10-11T00:00:00Z', 'captured_at' => '2026-10-11T00:00:00Z' }
  end
  let(:source) { described_class.new(metadata) }
  let(:artifact) { Recruiting::AcquisitionArtifact.new(source) }
  let(:url) { Recruiting::HtmlPage.source_url(2026) }
  let(:html) { Rails.root.join('spec/fixtures/recruiting/page1.html').read }
  let(:second_html) { Rails.root.join('spec/fixtures/recruiting/page2.html').read }
  let(:second_url) { Recruiting::HtmlPage.new(html, url, 2026).next_url }

  before { allow(described_class).to receive(:sleep) }

  def saved_page(content, page_url)
    Tempfile.create(['recruiting-page', '.html']) do |file|
      file.write(content)
      file.flush
      source.saved([{ 'path' => file.path, 'url' => page_url }])
    end
  end

  it 'extracts observed markup and preserves exact text, decimal values and raw HTML bytes' do
    saved_page(html, url)
    expect(source.rows.first).to include('team_label' => 'Arkansas', 'raw_team_label' => 'Arkansas ',
                                         'class_points' => '70.43', 'rank' => '1', 'commit_count' => '8', 'average_rating' => '97.92')
    expect(Base64.strict_decode64(source.pages.first.fetch('html_base64'))).to eq(html)
    expect(source.pages.first.fetch('sha256')).to eq(Digest::SHA256.hexdigest(html))
    expect(source.next_url).to eq(second_url)
    Dir.mktmpdir do |root|
      path = artifact.save(root)
      expect(Recruiting::Dataset.load(path).manifest.dig('metadata', 'snapshot_kind')).to eq('raw_html_bundle')
    end
  end

  it 'parses ordered saved pagination fragments deterministically' do
    saved_page(html, url)
    saved_page(second_html, second_url)
    expect(source.rows.pluck('rank')).to eq(%w[1 51])
    expect(source.pages.size).to eq(2)
    expect(artifact.extract.fetch('coverage_note')).to include('2 pages captured, 2 rows')
  end

  it 'fetches the actual advertised next URL and stops at the explicit page limit' do
    allow(HTTParty).to receive(:get).with(url, anything).and_return(double(code: 200, body: html))
    allow(HTTParty).to receive(:get).with(second_url, anything).and_return(double(code: 200, body: second_html))
    source.fetch(2)
    expect(source.status).to eq('ok')
    expect(source.rows.pluck('rank')).to eq(%w[1 51])
    expect(source.next_url).to include('Page=3')
  end

  it 'retains successful pages and a failed response without producing preparable evidence' do
    allow(HTTParty).to receive(:get).with(url, anything).and_return(double(code: 200, body: html))
    allow(HTTParty).to receive(:get).with(second_url, anything).and_return(double(code: 403, body: 'Access denied'))
    source.fetch(3)
    expect(source.status).to eq('access_failure')
    expect(source.rows.size).to eq(1)
    Dir.mktmpdir do |root|
      path = artifact.save(root)
      expect(JSON.parse(File.read(File.join(path, 'original.json')))).to include('source_status' => 'access_failure')
      expect { Recruiting::Dataset.new(File.read(File.join(path, 'original.json')), artifact.snapshot) }
        .to raise_error(ArgumentError, /Source failure/)
    end
  end

  it 'distinguishes network failure from empty coverage' do
    allow(HTTParty).to receive(:get).and_raise(Timeout::Error)
    source.fetch(2)
    expect(source.status).to eq('network_failure')
    expect(source.rows).to be_empty
  end

  it 'rejects challenge/unrecognized HTML even with HTTP 200' do
    saved_page('<html>Access denied</html>', url)
    expect(source.status).to eq('parse_failure')
    expect(source.rows).to be_empty
    expect(source.pages.size).to eq(1)
  end

  it 'recognizes an empty first-page ranking container' do
    empty = Nokogiri::HTML(html)
    empty.css('.rankings-page__list-item').remove
    empty.css('a[data-js="showmore"]').remove
    empty.at_css('body').add_child('<ul class="rankings-page__list"></ul>')
    saved_page(empty.to_html, url)
    expect(source.status).to eq('ok')
    expect(source.rows).to be_empty
  end

  it 'rejects wrong categories, source years, conference filters and cross-host pagination' do
    expect { Recruiting::HtmlPage.new(html.sub('2026 Recruit', '2026 Transfer'), url, 2026) }.to raise_error(ArgumentError)
    expect { Recruiting::HtmlPage.new(html, url, 2025) }.to raise_error(ArgumentError)
    expect { Recruiting::HtmlPage.new(html.sub('>ALL<', '>ACC<'), url, 2026) }.to raise_error(ArgumentError)
    changed = html.sub(second_url.gsub('&', '&amp;'), 'https://example.com/page2')
    expect { Recruiting::HtmlPage.new(changed, url, 2026).next_url }.to raise_error(ArgumentError)
  end

  it 'rejects pagination loops and unordered saved pages' do
    saved_page(html, second_url)
    expect(source.status).to eq('parse_failure')
    fresh = described_class.new(metadata)
    allow(HTTParty).to receive(:get).and_return(double(code: 200, body: html))
    fresh.fetch(3)
    expect(fresh.status).to eq('parse_failure')
    expect(fresh.failure).to include('cycle')
  end

  it 'leaves missing fields unknown and lets preview exclude malformed supplied points' do
    changed = html.sub('70.43', 'NaN').sub('97.92', '')
    saved_page(changed, url)
    row = Recruiting::Row.new(source.rows.first, 1).to_h
    expect(row.dig('values', 'average_rating')).to be_nil
    expect(row.fetch('errors')).to include(/class_points/)
  end

  it 'retains an observed generic team URL as missing provider identity rather than inventing a slug' do
    changed = html.gsub('https://247sports.com/college/arkansas/season/2026-basketball/commits/',
                        'https://247sports.com/season/2026-basketball/commits/')
    saved_page(changed, url)
    expect(source.status).to eq('ok')
    expect(source.rows.first.fetch('provider_team_id')).to be_nil
    expect(Recruiting::Row.new(source.rows.first, 1).to_h.fetch('errors')).to include(/provider_team_id/)
  end

  it 'reports malformed saved entries and timestamp overrides as explicit failures' do
    source.saved(['not an entry'])
    expect(source.status).to eq('parse_failure')
    fresh = described_class.new(metadata)
    fresh.saved([{ 'path' => Rails.root.join('spec/fixtures/recruiting/page1.html').to_s,
                   'url' => url, 'captured_at' => 'not a timestamp' }])
    expect(fresh.status).to eq('parse_failure')
  end

  it 'retains failed artifacts for malformed canonical and pagination URLs in saved and live HTML' do
    malformed = html.sub(url, 'https://[broken')
    saved_page(malformed, url)
    expect(source.status).to eq('parse_failure')
    Dir.mktmpdir do |root|
      expect(File.read(File.join(artifact.save(root), 'snapshot'))).to include(Base64.strict_encode64(malformed))
    end
    fresh = described_class.new(metadata)
    pagination = html.sub(second_url.gsub('&', '&amp;'), 'https://[broken')
    allow(HTTParty).to receive(:get).and_return(double(code: 200, body: pagination))
    fresh.fetch(2)
    expect(fresh.status).to eq('parse_failure')
    Dir.mktmpdir do |root|
      saved = Recruiting::AcquisitionArtifact.new(fresh).save(root)
      expect(File.read(File.join(saved, 'snapshot'))).to include(Base64.strict_encode64(pagination))
    end
  end
end
