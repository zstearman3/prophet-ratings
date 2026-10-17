# frozen_string_literal: true

module Recruiting
  # Converts source captures into retained database attributes, including failed responses.
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
        'snapshot_kind' => 'raw_html_bundle', 'snapshot_location' => 'RecruitingBatch.snapshot_bytes (base64 exact page bytes)',
        'extraction_version' => Extract::VERSION, 'html_parser_version' => 1,
        'coverage_note' => "#{pages.size} pages captured, #{rows.size} rows; next page: #{@source.next_url || 'none advertised'}; " \
                           'annual completeness not independently verified',
        'pages' => pages.map { |page| page.except('html_base64') }, 'failure' => @source.failure, 'rows' => rows
      )
    end

    def snapshot
      JSON.pretty_generate('pages' => @source.pages)
    end

    def database_attributes
      document = extract
      original = "#{JSON.pretty_generate(document)}\n"
      captured = snapshot
      database_metadata(document).merge(extract_bytes: original, snapshot_bytes: captured,
                                        dataset_revision: database_revision(original, captured))
    end

    def database_metadata(document)
      status = @source.status
      { status: status == 'ok' ? 'ready' : 'failed', source_status: status,
        failure_message: @source.failure&.to_json, coverage_note: document.fetch('coverage_note'),
        page_count: @source.pages.size, next_url: @source.next_url }
    end

    private

    def database_revision(original, captured)
      Dataset.new(original, captured).manifest.fetch('dataset_revision') if @source.status == 'ok'
    end
  end
end
