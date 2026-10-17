# frozen_string_literal: true

namespace :offseason_inputs do
  desc 'Preview/apply reviewed departure evidence for existing YEAR with KIND, INPUT_HASH, VERSION and REASON'
  task import: :environment do
    kind = ENV.fetch('KIND')
    raise ArgumentError, 'Only departures use file imports; review recruiting in the season admin UI.' unless kind == 'departures'

    season = Season.find_by!(year: SeasonPreparer.parse_year(ENV.fetch('YEAR')))
    paths = { review_path: ENV.fetch('REVIEW_PATH'),
              capture_dir: ENV.fetch('CAPTURE_DIR', nil), dataset_path: ENV.fetch('DATASET_PATH', nil) }
    publication = { version: ENV.fetch('VERSION'), reason: ENV.fetch('REASON'), input_hash: ENV.fetch('INPUT_HASH'),
                    predecessor_id: ENV.fetch('PREDECESSOR_ID', nil) && Integer(ENV.fetch('PREDECESSOR_ID'), 10) }
    importer = OffseasonInputs::Import.new(season:, kind:, paths:, publication:)
    report = ENV['APPLY'] == 'true' ? importer.call(preview_key: ENV.fetch('PREVIEW_KEY')) : importer.preview
    puts JSON.pretty_generate(report.except('payload').merge('coverage' => report.dig('payload', 'report'),
                                                             'team_inputs' => report.dig('payload', 'team_inputs')))
  rescue ArgumentError, KeyError, JSON::ParserError, SystemCallError, ActiveRecord::ActiveRecordError => e
    abort("Offseason evidence import failure: #{e.message}")
  end
end
