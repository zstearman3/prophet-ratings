# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Net::HTTP never follows a redirect, keeping bearer credentials on this host.
    class HttpTransport
      def self.call(uri, key)
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{key}"
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |connection|
          response = connection.request(request)
          { status: response.code.to_i, body: response.body, headers: response.to_hash.transform_values(&:first) }
        end
      end
    end
  end
end
