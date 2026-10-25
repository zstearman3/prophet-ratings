# frozen_string_literal: true

# Prints an alignment result consistently for rake tasks and bootstrap.
class SeasonConferenceAlignmentReporter
  def initialize(result:, year:)
    @result = result
    @year = year
  end

  def call(output: $stdout)
    @output = output
    output.puts "Conference alignment: year=#{year} source=#{result.source_url}"
    %i[created changed unchanged].each { |category| report_category(category) }
    report_suggestions
  end

  private

  attr_reader :result, :year, :output

  def report_category(category)
    entries = result.public_send(category)
    output.puts "#{category.capitalize} memberships: #{entries.size}"
    entries.each { |entry| output.puts "  #{entry}" }
  end

  def report_suggestions
    suggestions = result.suggestions
    output.puts "REVIEW REQUIRED: #{suggestions.size} suggestion(s)"
    suggestions.each { |suggestion| output.puts "  #{suggestion}" }
  end
end
