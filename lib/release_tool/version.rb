# frozen_string_literal: true

require_relative '../release_tool'

module ReleaseTool
  # Numeric suffix ordering also works after the 99th release in one day.
  class Version
    def initialize(tags, date:)
      @tags = tags
      @base = "v#{date.strftime('%Y.%m.%d')}"
    end

    def choose(options)
      tag = options[:tag]
      return self.class.validate(tag) if tag

      daily = @tags.grep(/\A#{Regexp.escape(@base)}(?:\.\d{2,})?\z/)
      options[:update] ? latest(daily) : next_tag(daily)
    end

    def self.validate(tag)
      raise Error, 'Release tags must use vYYYY.MM.DD or vYYYY.MM.DD.NN.' unless tag.match?(/\Av\d{4}\.\d{2}\.\d{2}(?:\.\d{2,})?\z/)

      Date.strptime(tag[1, 10], '%Y.%m.%d')
      tag
    rescue Date::Error
      raise Error, 'Release tag contains an invalid date.'
    end

    private

    def next_tag(tags)
      return @base if tags.empty?

      "#{@base}.#{format('%02d', tags.map { |value| suffix(value) }.max + 1)}"
    end

    def latest(tags)
      raise Error, "No release tag exists for #{@base}; pass an explicit draft tag to --update." if tags.empty?

      tags.max_by { |value| suffix(value) }
    end

    def suffix(tag)
      tag == @base ? 0 : tag.delete_prefix("#{@base}.").to_i
    end
  end
end
