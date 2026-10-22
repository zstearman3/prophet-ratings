# frozen_string_literal: true

namespace :departures do
  desc 'Acquire bounded annual CBBD JSON into a new private immutable directory'
  task acquire: :environment do
    plan = JSON.parse(File.read(ENV.fetch('PLAN_PATH')))
    Departures::Contract.years!(plan)
    directory = ENV.fetch('OUTPUT_DIR')
    raise ArgumentError, 'OUTPUT_DIR already exists; use a successor capture directory' if File.exist?(directory)

    # Validate source configuration before any requests.
    Departures::CbbdDataset.validate_plan(plan)
    FileUtils.mkdir_p(directory, mode: 0o700)
    checkpoint = Departures::FileCheckpoint.new(File.join(directory, 'manifest.partial.json'))
    manifest = Departures::CbbdAcquisition.new(plan:, directory:, checkpoint:).call
    Departures::Contract.write(File.join(directory, 'manifest.json'), manifest)
    dataset = Departures::AnnualDataset.new(manifest:, directory:).call
    Departures::Contract.write(File.join(directory, 'dataset.json'), dataset)
    puts JSON.pretty_generate(dataset.slice('dataset_revision', 'failures'))
    abort 'Partial acquisition; preserve captures and review failures' if dataset.fetch('failures').any?
  end

  desc 'Reparse exact saved source bytes without network requests or database writes'
  task replay: :environment do
    directory = ENV.fetch('CAPTURE_DIR')
    manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
    dataset = Departures::AnnualDataset.new(manifest:, directory:).call
    Departures::Contract.write(ENV.fetch('DATASET_PATH'), dataset)
    puts JSON.pretty_generate(dataset.slice('dataset_revision', 'failures'))
    abort 'Partial acquisition; review failures' if dataset.fetch('failures').any?
  end

  desc 'Validate an annual saved bundle and optional reviewed identity decisions; print read-only loss coverage'
  task preview: :environment do
    directory = ENV.fetch('CAPTURE_DIR')
    manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
    dataset = Departures::AnnualDataset.new(manifest:, directory:).call
    saved = JSON.parse(File.read(ENV.fetch('DATASET_PATH')))
    raise ArgumentError, 'Saved dataset differs from source replay' unless saved == dataset

    review = ENV['REVIEW_PATH'] ? JSON.parse(File.read(ENV.fetch('REVIEW_PATH'))) : {}
    report = Departures::Preview.new(dataset:, review:).call
    puts JSON.pretty_generate(report)
    abort 'Incomplete departure coverage; review unknowns/failures' unless report.fetch('coverage_complete')
  end
end
