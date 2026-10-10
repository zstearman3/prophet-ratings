# frozen_string_literal: true

namespace :import do
  desc 'Import base team, season, and conference data without reconciling conference memberships'
  task base: :environment do
    Importer::Setup::BaseDataImporter.run
  end

  desc 'Preview authoritative conference CSV changes; APPLY=true explicitly permits updates and deletions'
  task reconcile_conferences: :environment do
    apply = ENV.fetch('APPLY', 'false')
    abort 'APPLY must be true or false' unless %w[true false].include?(apply)

    path = ENV['CSV_PATH'].presence || Rails.root.join('db/seeds/team_conferences.csv')
    synchronizer = Importer::Setup::TeamConferencesSynchronizer.new(path:, apply: apply == 'true')
    result = synchronizer.call
    puts "Conference CSV #{apply == 'true' ? 'applied' : 'preview'}: #{result.to_h.inspect}"
    synchronizer.changes.each { |change| puts change.to_json }
    puts 'Rows absent from this CSV are deletion candidates. Review before rerunning with APPLY=true.' unless apply == 'true'
  rescue Importer::Setup::TeamConferencesSynchronizer::InvalidData, Errno::ENOENT => e
    abort "Conference CSV reconciliation failed: #{e.message}"
  end

  desc 'Scrape and import games'
  task games: :environment do
    Season.order(year: :asc).each do |season|
      puts JSON.pretty_generate(SyncFullSeasonGamesJob.new.perform(season))
    end
  rescue SyncFullSeasonGamesJob::IncompleteSync => e
    puts JSON.pretty_generate(e.report)
    abort(e.message)
  rescue ArgumentError => e
    abort(e.message)
  end
end
