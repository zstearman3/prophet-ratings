# frozen_string_literal: true

module Departures
  # Keeps uploaded bytes unmodified and requires their actual normal-access metadata.
  class UploadedSource
    def initialize(source, attributes)
      @source = source
      @attributes = attributes
    end

    def call
      validate_origin
      original = bytes
      sha = Digest::SHA256.hexdigest(original)
      capture = source.except('failure').merge(metadata, 'http_status' => 200, 'snapshot_kind' => 'raw_html',
                                                         'snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.html")
      [capture, { 'snapshot_base64' => Base64.strict_encode64(original) }]
    end

    private

    attr_reader :source, :attributes

    def bytes
      upload = attributes.fetch('html')
      self.class.validate_upload(upload)
      original = upload.read(BatchAcquisition::MAX_UPLOAD + 1).to_s.b
      Contract.check!(original.present? && original.bytesize <= BatchAcquisition::MAX_UPLOAD,
                      'Saved HTML must contain bytes and be at most 5 MiB')
      original
    end

    def metadata
      fields = attributes.slice('captured_at', 'observed_at', 'source_as_of', 'source_as_of_reason')
      fields['source_as_of'] = attributes['source_as_of'].presence
      self.class.validate_metadata(fields)
      fields
    end

    public_class_method def self.validate_upload(upload)
      Contract.check!(upload.is_a?(ActionDispatch::Http::UploadedFile) || upload.is_a?(StringIO), 'Choose the original saved HTML file')
    end

    public_class_method def self.validate_metadata(fields)
      %w[captured_at observed_at].each { |key| Time.iso8601(fields.fetch(key)) }
      validate_as_of(fields)
    end

    public_class_method def self.validate_as_of(fields)
      as_of = fields['source_as_of']
      as_of ? Time.iso8601(as_of) : Contract.text!(fields['source_as_of_reason'], 'source_as_of_reason')
    end

    def validate_origin
      Contract.check!(attributes.fetch('url') == source.fetch('url'), 'Recovery URL must match the configured source')
      Contract.check!(attributes.fetch('http_status').to_s == '200', 'Recovery requires the actual successful HTTP 200 response')
    end
  end
end
