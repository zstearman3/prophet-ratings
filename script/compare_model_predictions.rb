# frozen_string_literal: true

# Run with bin/rails runner; this script reads saved forecasts and never calculates ratings.
require 'optparse'

options = {}
parser = OptionParser.new do |flags|
  flags.banner = 'Usage: bin/rails runner script/compare_model_predictions.rb --year YEAR --baseline MODEL --candidate MODEL [options]'
  flags.on('--year YEAR', Integer, 'Season ending year, e.g. 2026') { |value| options[:year] = value }
  flags.on('--baseline MODEL', 'Published baseline model name') { |value| options[:baseline] = value }
  flags.on('--candidate MODEL', 'Published candidate model name') { |value| options[:candidate] = value }
  flags.on('--baseline-mode TYPE', 'Default: legacy_unverified') { |value| options[:baseline_mode] = value }
  flags.on('--candidate-mode TYPE', 'Default: reconstruction') { |value| options[:candidate_mode] = value }
  flags.on('--from DATE', 'Inclusive Eastern YYYY-MM-DD; default: season start') { |value| options[:from] = value }
  flags.on('--through DATE', 'Inclusive Eastern YYYY-MM-DD; default: season end') { |value| options[:through] = value }
  flags.on('--csv PATH', 'Optional paired per-game errors CSV (overwrites PATH)') { |value| options[:csv] = value }
  flags.on('-h', '--help', 'Show usage') do
    puts flags
    exit
  end
end

begin
  parser.parse!(ARGV)
  raise ArgumentError, "Unexpected arguments: #{ARGV.join(' ')}" if ARGV.any?

  missing = %i[year baseline candidate].reject { |key| options.key?(key) }
  raise ArgumentError, "Required options: #{missing.join(', ')}" if missing.any?

  season = Season.find_by!(year: options.delete(:year))
  baseline = RatingsConfigVersion.find_by!(name: options.delete(:baseline))
  candidate = RatingsConfigVersion.find_by!(name: options.delete(:candidate))
  csv_path = options.delete(:csv)
  report = ProphetRatings::PredictionComparisonReport.new(season:, baseline:, candidate:, **options)
  puts report.text
  if csv_path
    File.write(csv_path, report.csv)
    puts "Per-game errors written to #{csv_path}"
  end
rescue OptionParser::ParseError, ArgumentError, ActiveRecord::RecordNotFound, SystemCallError => error
  warn "Comparison failed: #{error.message}"
  exit 1
end
