# frozen_string_literal: true

require 'net/http'

module OffseasonPerformance
  # Drives real Devise/CSRF sessions; each concurrent client owns independent cookies.
  class Client
    def initialize(session = {})
      @cookies = session.fetch('cookies', {})
      @token = session['token']
    end

    def request(method, path, **options)
      uri = URI("http://web:3000#{path}")
      request = Client.build_request(method, uri, options.merge(headers: headers(options.fetch(:id, 'setup'))))
      response = Client.perform(uri, request)
      retain_cookies(response)
      response
    end

    def self.build_request(method, uri, options)
      request = method.new(uri, options.fetch(:headers))
      request.set_form_data(options.fetch(:values, {})) if request.request_body_permitted?
      request
    end

    def headers(id)
      { 'Cookie' => @cookies.map { |key, value| "#{key}=#{value}" }.join('; '),
        'X-Benchmark-Id' => id, 'X-CSRF-Token' => @token }.compact
    end

    def self.perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, read_timeout: 180, open_timeout: 5) do |http|
        http.max_retries = 0
        http.request(request)
      end
    end

    def retain_cookies(response)
      response.get_fields('set-cookie')&.each do |cookie|
        key, value = cookie.split(';').first.split('=', 2)
        @cookies[key] = value
      end
    end

    def authenticate
      sign_in
      refresh_csrf
      { 'cookies' => @cookies, 'token' => @token }
    end

    def sign_in
      @token = Client.csrf(request(Net::HTTP::Get, '/users/sign_in'))
      raise 'Missing Devise CSRF token' unless @token

      response = request(Net::HTTP::Post, '/users/sign_in', values: { 'user[email]' => 'benchmark@example.test',
                                                                      'user[password]' => 'SyntheticBenchmark!2026' })
      Client.verify_login(response)
    end

    def self.verify_login(response)
      status = response.code.to_i
      raise "Devise sign-in failed #{status}" unless status == 303
    end

    def refresh_csrf
      season_id = JSON.parse(File.read('/benchmark/fixture.json')).fetch('season_id')
      page = request(Net::HTTP::Get, "/admin/preseason_publications?season_id=#{season_id}")
      @token = Client.csrf(page)
      raise 'Authenticated CSRF token absent' unless page.code.to_i == 200 && @token
    end

    def self.csrf(response)
      Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]('content')
    end
  end
end
