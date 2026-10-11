# frozen_string_literal: true

module Recruiting
  # Approval pins an exact preview; later alias/evidence changes require a new review.
  class MappingReview
    def initialize(report)
      @report = report
    end

    def approve(document)
      raise ArgumentError, 'Review must pin dataset_revision and mapping_revision from the current preview' unless current?(document)
      unless Extract.text?(document['approved_by'])
        raise ArgumentError,
              'Review requires approved_by and approved_at'
      end

      Extract.timestamp(document['approved_at'])
      @report.merge('review_status' => 'reviewed', 'approval' => document.slice('approved_by', 'approved_at'))
    end

    def save(root, document)
      approved = approve(document)
      FileUtils.mkdir_p(root)
      path = File.join(root, "#{@report.fetch('mapping_revision')}.json")
      self.class.write_exclusive(path, "#{JSON.pretty_generate(approved)}\n")
      path
    end

    def self.write_exclusive(path, bytes)
      return if File.exist?(path) && File.binread(path) == bytes

      File.open(path, File::WRONLY | File::CREAT | File::EXCL) { |file| file.write(bytes) }
    end

    def self.review_keys(document)
      document.slice('dataset_revision', 'mapping_revision') if document.is_a?(Hash)
    end

    private

    def current?(document)
      @report.slice('dataset_revision', 'mapping_revision') == self.class.review_keys(document)
    end
  end
end
