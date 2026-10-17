# frozen_string_literal: true

require 'date'
require 'json'
require 'open3'
require 'tempfile'

# Standalone release preparation; does not load Rails or deploy the application.
module ReleaseTool
  # A failed prerequisite or command stops release preparation.
  class Error < StandardError; end

  def self.capture(*arguments)
    command = arguments.first
    output, error, status = Open3.capture3({ 'GH_REPO' => nil }, *arguments)
    raise Error, "#{command} failed: #{error.strip}" unless status.success?

    output
  rescue Errno::ENOENT
    raise Error, "Install #{command} and ensure it is on PATH."
  end

  def self.json(*)
    JSON.parse(capture(*))
  rescue JSON::ParserError
    raise Error, 'A command returned invalid JSON.'
  end
end
