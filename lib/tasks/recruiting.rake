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

namespace :recruiting do
  desc 'Create annual recruiting evidence: SOURCE_YEAR, YEAR, CATEGORY, OUTPUT_DIR; optional PAGES_PATH saved HTML manifest'
  task acquire: :environment do
    metadata = {
      'source_year' => SeasonPreparer.parse_year(ENV.fetch('SOURCE_YEAR')),
      'target_season' => SeasonPreparer.parse_year(ENV.fetch('YEAR')), 'category' => ENV.fetch('CATEGORY')
    }
    acquisition = Recruiting::Acquisition.new(metadata)
    if ENV['PAGES_PATH'].present?
      manifest = JSON.parse(File.read(ENV.fetch('PAGES_PATH')))
      raise ArgumentError, 'Saved page manifest must be an object' unless manifest.is_a?(Hash)

      %w[observed_at retrieved_at captured_at].each do |key|
        value = manifest.fetch(key)
        Recruiting::Extract.timestamp(value)
        metadata[key] = value
      end
      acquisition.saved(manifest.fetch('pages'))
    else
      now = Time.now.utc.iso8601
      metadata.merge!('observed_at' => now, 'retrieved_at' => now, 'captured_at' => now)
      acquisition.fetch(Integer(ENV.fetch('MAX_PAGES', '20')))
      metadata.update('retrieved_at' => Time.now.utc.iso8601, 'captured_at' => Time.now.utc.iso8601)
    end
    path = Recruiting::AcquisitionArtifact.new(acquisition).save(ENV.fetch('OUTPUT_DIR'))
    puts JSON.pretty_generate('dataset_dir' => path, 'source_status' => acquisition.status,
                              'rows' => acquisition.rows.size, 'next_url' => acquisition.next_url, 'failure' => acquisition.failure)
    abort('Acquisition failed; evidence retained, use saved HTML fallback') unless acquisition.status == 'ok'
  rescue ArgumentError, KeyError, JSON::ParserError, SystemCallError => e
    abort("Recruiting acquisition failure: #{e.message}")
  end
end
