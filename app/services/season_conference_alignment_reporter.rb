# frozen_string_literal: true

# Prints an alignment result consistently for rake tasks and bootstrap.
class SeasonConferenceAlignmentReporter
  def initialize(result:, year:)
    @result = result
    @year = year
  end

  def call(output: $stdout)
    output.puts "Conference alignment: year=#{year} source=#{result.source_url}"
    %i[created changed unchanged].each do |category|
      entries = result.public_send(category)
      output.puts "#{category.capitalize} memberships: #{entries.size}"
      entries.each { |entry| output.puts "  #{entry}" }
    end
    output.puts "REVIEW REQUIRED: #{result.suggestions.size} suggestion(s)"
    result.suggestions.each { |suggestion| output.puts "  #{suggestion}" }
  end

  private

  attr_reader :result, :year
end
