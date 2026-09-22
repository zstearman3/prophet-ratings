# frozen_string_literal: true

namespace :season do
  desc 'Align conference memberships from Sports Reference (YEAR defaults to latest stored season)'
  task align_conferences: :environment do
    align_season_conferences(ENV.fetch('YEAR') { Season.maximum(:year) })
  end

  def align_season_conferences(year)
    alignment = SeasonConferenceAlignment.new(year:)
    result = alignment.call
    SeasonConferenceAlignmentReporter.new(result:, year:).call
    return if result.success?

    abort("Safe changes saved. Resolve suggestions in RailsAdmin/stored identities, then rerun season:align_conferences YEAR=#{year}.")
  rescue ArgumentError, SeasonConferenceAlignment::Error, Scraper::ConferenceStandingsScraper::Error => e
    abort("Conference alignment failed for year=#{year}: #{e.message}")
  end
end
