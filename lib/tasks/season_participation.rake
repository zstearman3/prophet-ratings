# frozen_string_literal: true

namespace :season do
  desc 'Save an explicit operator roster review from REVIEW_PATH JSON; requires YEAR; does not publish ratings'
  task review_participation: :environment do
    season = Season.find_by!(year: SeasonPreparer.parse_year(ENV.fetch('YEAR', '')))
    document = JSON.parse(File.read(ENV.fetch('REVIEW_PATH')))
    review = SeasonParticipationReview.new(season)
    review.apply(document)
    puts "Saved participation review for season ID #{season.id}; no ratings or snapshots changed."
    review.validate
    puts 'Roster/date/alias coverage passed. Initialize and review ratings before activation.'
  rescue ArgumentError, KeyError, Season::OperationInProgress => e
    abort(e.message)
  end
end
