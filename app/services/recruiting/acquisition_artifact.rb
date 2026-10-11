# frozen_string_literal: true

module Recruiting
  # Successful acquisition uses immutable datasets; failed responses remain auditable.
  class AcquisitionArtifact
    def initialize(source)
      @source = source
    end

    def extract
      pages = @source.pages
      rows = @source.rows
      @source.metadata.merge(
        'provider' => Extract::SOURCE, 'conference_scope' => 'all', 'source_status' => @source.status,
        'source_url' => HtmlPage.source_url(@source.year), 'source_as_of' => nil,
        'source_as_of_reason' => 'Displayed source update text retained per page; timezone not independently verified',
        'snapshot_kind' => 'raw_html_bundle', 'snapshot_location' => 'snapshot (JSON with base64 exact page bytes)',
        'extraction_version' => Extract::VERSION, 'html_parser_version' => 1,
        'coverage_note' => "#{pages.size} pages captured, #{rows.size} rows; next page: #{@source.next_url || 'none advertised'}; " \
                           'annual completeness not independently verified',
        'pages' => pages.map { |page| page.except('html_base64') }, 'failure' => @source.failure, 'rows' => rows
      )
    end

    def snapshot
      JSON.pretty_generate('pages' => @source.pages)
    end

    def save(root)
      bytes = "#{JSON.pretty_generate(extract)}\n"
      return Dataset.new(bytes, snapshot).save(root) if @source.status == 'ok'

      save_failure(root, bytes)
    end

    private

    def save_failure(root, bytes)
      directory = File.join(root, "failed-#{Digest::SHA256.hexdigest("#{bytes}:#{snapshot}")}")
      FileUtils.mkdir_p(directory)
      MappingReview.write_exclusive(File.join(directory, 'original.json'), bytes)
      MappingReview.write_exclusive(File.join(directory, 'snapshot'), snapshot)
      directory
    end
  end
end
