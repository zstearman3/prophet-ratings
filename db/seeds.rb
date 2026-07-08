# frozen_string_literal: true

Importer::Setup::BaseDataImporter.run

path = Rails.root.join('db/seeds/team_conferences.csv')
Importer::Setup::TeamConferencesSynchronizer.referenced_years(path:).each do |year|
  SeasonPreparer.new(year:).call
end

result = Importer::Setup::TeamConferencesSynchronizer.new(path:).call
# rubocop:disable Rails/Output
puts "Team conferences synchronized: #{result.to_h.inspect}"
# rubocop:enable Rails/Output
