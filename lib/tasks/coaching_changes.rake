# frozen_string_literal: true

namespace :coaching do
  desc 'Discover pending D1 coaching candidates for an explicit ending YEAR (manual review required)'
  task discover: :environment do
    result = CoachingChangesImport.new(year: ENV.fetch('YEAR', nil)).call
    puts JSON.pretty_generate(result)
    puts 'Review candidate IDs in Rails Admin; confirm/reject manually, then explicitly mark the year ready.'
  rescue ArgumentError, Scraper::CoachingChangesScraper::Error, ActiveRecord::ActiveRecordError => error
    abort("Coaching discovery failed; no import changes saved: #{error.message}")
  end
end
