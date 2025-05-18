# frozen_string_literal: true

namespace :import do
  desc 'Import base team, season, and conference data'
  task base: :environment do
    Importer::Setup::BaseDataImporter.run
  end

  desc 'Scrape and import games'
  task games: :environment do
    Season.order(year: :asc).each do |season|
      SyncFullSeasonGamesJob.perform_now(season)
    end
  end
end
