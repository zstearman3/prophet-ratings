# frozen_string_literal: true

require 'net/http'
require 'uri'
require_relative '../release_tool'

module ReleaseTool
  # Reads linked pages only; never searches by title or changes ticket statuses.
  class Notion
    LINK = %r{https://(?:[a-z0-9-]+\.)?notion\.(?:so|com|site)/[^\s<>()\[\]]+}i
    PAGE_ID = /([0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12})\z/i

    def initialize(token: ENV.fetch('NOTION_TOKEN', nil))
      @token = token
      @pages = {}
    end

    def tickets(text)
      self.class.ids(text).uniq.map { |id| @pages[id] ||= lookup(id) }
    end

    def self.ids(text)
      text.to_s.scan(LINK).filter_map { |url| url.split(/[?#]/, 2).first[PAGE_ID, 1]&.delete('-') }
    end

    def self.ticket(page, id)
      properties = page.fetch('properties', {})
      title = properties.values.find { |property| property['type'] == 'title' }&.fetch('title', []) || []
      { title: title.map { |part| part['plain_text'] || part.dig('text', 'content') }.join,
        status: properties.dig('Status', 'status', 'name') || properties.dig('Status', 'select', 'name') || 'Notion unavailable',
        url: "https://www.notion.so/#{id}" }
    end

    def self.document(page)
      return page if page.is_a?(Hash) && page['properties'].is_a?(Hash)

      raise Error, 'Malformed Notion page.'
    end

    def self.read(response)
      raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      document(JSON.parse(response.body))
    end

    def self.failed_lookup(id, error)
      detail = error.is_a?(Error) ? error.message : error.class.name
      warn "Notion lookup #{id} failed (#{detail}); retaining its link with unavailable status."
      {}
    end

    private

    def lookup(id)
      page = @token.to_s.empty? ? {} : request(id)
      self.class.ticket(page, id)
    end

    def request(id)
      reader = self.class
      response = response_for(id)
      reader.read(response)
    rescue Error, JSON::ParserError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
      reader.failed_lookup(id, error)
    end

    def response_for(id)
      sleep(0.35)
      uri = URI("https://api.notion.com/v1/pages/#{id}")
      headers = { 'Authorization' => "Bearer #{@token}", 'Notion-Version' => '2025-09-03' }
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(Net::HTTP::Get.new(uri, headers))
      end
    end
  end
end
