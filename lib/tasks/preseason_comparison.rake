# frozen_string_literal: true

namespace :ratings do
  desc 'Read-only preseason benchmark; requires YEARS (one to five comma-separated years) and SOURCE_CONFIG'
  task compare_preseason: :environment do
    years = ENV.fetch('YEARS').split(',')
    report = ProphetRatings::PreseasonComparison.new(years:, source_config_name: ENV.fetch('SOURCE_CONFIG')).call
    puts JSON.pretty_generate(report)
  end
end
