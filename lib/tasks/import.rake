# frozen_string_literal: true

namespace :import do
  desc 'Import base team, season, and conference data'
  task base: :environment do
    Importer::BaseDataImporter.run
  end
end
