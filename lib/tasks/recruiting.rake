# frozen_string_literal: true

namespace :recruiting do
  desc 'Prepare immutable saved 247 Recruit Composite evidence from EXTRACT_PATH and SNAPSHOT_PATH into OUTPUT_DIR'
  task prepare: :environment do
    dataset = Recruiting::Dataset.new(File.binread(ENV.fetch('EXTRACT_PATH')), File.binread(ENV.fetch('SNAPSHOT_PATH')))
    puts dataset.save(ENV.fetch('OUTPUT_DIR'))
  rescue ArgumentError, KeyError, JSON::ParserError, SystemCallError => e
    abort("Recruiting source/prepare failure: #{e.message}")
  end

  desc 'Preview DATASET_DIR for explicit YEAR; optionally save pinned REVIEW_PATH approval into MAPPING_DIR'
  task preview: :environment do
    season = Season.find_by!(year: SeasonPreparer.parse_year(ENV.fetch('YEAR')))
    report = Recruiting::Preview.new(Recruiting::Dataset.load(ENV.fetch('DATASET_DIR')), season).call
    if ENV['REVIEW_PATH'].present?
      approval = JSON.parse(File.read(ENV.fetch('REVIEW_PATH')))
      puts Recruiting::MappingReview.new(report).save(ENV.fetch('MAPPING_DIR'), approval)
    end
    puts JSON.pretty_generate(report)
  rescue ArgumentError, KeyError, JSON::ParserError, SystemCallError, ActiveRecord::RecordNotFound => e
    abort("Recruiting source/preview failure: #{e.message}")
  end
end
