# frozen_string_literal: true

require 'base64'

module Recruiting
  # Bounded source acquisition; failed evidence stays inspectable and cannot be prepared.
  class Acquisition
    attr_reader :pages, :rows, :metadata

    def year
      @metadata.fetch('source_year')
    end

    def next_url
      @state['next_url']
    end

    def status
      @state['status']
    end

    def failure
      @state['failure']
    end

    def initialize(metadata)
      @metadata = metadata
      validate_metadata
      @pages = []
      @rows = []
      @state = { 'next_url' => HtmlPage.source_url(year), 'status' => 'ok' }
    end

    def validate_metadata
      raise ArgumentError, 'Explicit Recruit Composite year Y must target Y+1' unless Extract.valid_year?(year) &&
                                                                                      @metadata['target_season'] == year + 1 &&
                                                                                      @metadata['category'] == Extract::CATEGORY
    end

    def saved(entries)
      raise ArgumentError, 'Supply at least one saved page entry' unless entries.is_a?(Array) && entries.any?

      entries.each { |entry| consume_saved(entry) }
    rescue ArgumentError, KeyError, SystemCallError => error
      fail_source('parse_failure', error)
    end

    def fetch(limit)
      raise ArgumentError, 'MAX_PAGES must be between 1 and 100' unless limit.between?(1, 100)

      limit.times do
        break unless next_url && status == 'ok'

        fetch_page
      end
      self
    end

    def self.request(url)
      sleep(1)
      response = HTTParty.get(url, timeout: 30, follow_redirects: false, headers: { 'User-Agent' => 'Mozilla/5.0' })
      [response.code, response.body.to_s]
    end

    def self.validated_entry(entry)
      %w[observed_at retrieved_at captured_at].each { |key| Extract.timestamp(entry.fetch(key)) }
      entry
    end

    private

    def consume_saved(entry)
      raise ArgumentError, 'Each saved page entry must be an object with path and URL' unless entry.is_a?(Hash)

      raise ArgumentError, 'Saved page list extends beyond advertised pagination' unless next_url

      url = entry.fetch('url')
      raise ArgumentError, 'Saved pages must follow the advertised pagination URLs in order' unless url == next_url

      capture(File.binread(entry.fetch('path')), entry)
    end

    def capture(html, details)
      entry = archive_page(html, details)
      parser = HtmlPage.new(html, details.fetch('url'), year)
      rows.concat(parser.rows)
      entry['source_updated_text'] = parser.source_updated_text
      update_next(parser.next_url)
    end

    def archive_page(html, details)
      entry = @metadata.slice('observed_at', 'retrieved_at', 'captured_at').merge(details.except('path'))
      entry['sha256'] = Digest::SHA256.hexdigest(html)
      entry['html_base64'] = Base64.strict_encode64(html)
      pages << self.class.validated_entry(entry)
      entry
    end

    def update_next(link)
      @state['next_url'] = link
      raise ArgumentError, 'Pagination cycle detected' if pages.pluck('url').include?(link)
    end

    def fetch_page
      receive_response(*self.class.request(next_url))
    rescue ArgumentError => error
      fail_source('parse_failure', error)
    rescue HTTParty::Error, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
      fail_source('network_failure', error)
    end

    def receive_response(code, html)
      details = { 'url' => next_url, 'http_status' => code }.merge(
        %w[observed_at retrieved_at captured_at].index_with { Time.now.utc.iso8601 }
      )
      return capture(html, details) if code == 200

      archive_page(html, details)
      fail_source('access_failure', "HTTP #{code} at #{next_url}; use saved HTML fallback")
    end

    def fail_source(kind, error)
      @state['status'] = kind
      @state['failure'] = error.to_s
      self
    end
  end
end
