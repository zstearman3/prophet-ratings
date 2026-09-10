# frozen_string_literal: true

namespace :season do
  desc 'Align conference memberships from Sports Reference (YEAR defaults to latest stored season)'
  task align_conferences: :environment do
    align_season_conferences(ENV.fetch('YEAR', Season.maximum(:year)))
  end

  def align_season_conferences(year)
    alignment = SeasonConferenceAlignment.new(year:)
    puts "Conference alignment: year=#{alignment.year} source=#{alignment.source_url}"
    result = alignment.call
    %i[created changed unchanged].each do |category|
      entries = result.public_send(category)
      puts "#{category.capitalize} memberships: #{entries.size}"
      entries.each { |entry| puts "  #{entry}" }
    end
    puts "REVIEW REQUIRED: #{result.suggestions.size} suggestion(s)"
    result.suggestions.each { |suggestion| puts "  #{suggestion}" }
    return if result.success?

    abort("Safe changes saved. Resolve suggestions in RailsAdmin/stored identities, then rerun season:align_conferences YEAR=#{year}.")
  rescue ArgumentError, SeasonConferenceAlignment::Error, Scraper::ConferenceStandingsScraper::Error => e
    abort("Conference alignment failed for year=#{year}: #{e.message}")
  end
end
