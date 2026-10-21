# frozen_string_literal: true

namespace :cbbd do
  desc 'Read a bounded CBBD window into private evidence files (no imports)'
  task dry_run: :environment do
    result = Ingestion::Cbbd::Adapter.new(
      season: ENV.fetch('SEASON'), start_date: ENV.fetch('START_DATE'), end_date: ENV.fetch('END_DATE'),
      capture_directory: ENV.fetch('CAPTURE_DIRECTORY'), api_key: ENV.fetch('CBBD_API_KEY')
    ).call
    puts JSON.generate(result.slice('run_id', 'bounds', 'complete', 'manifest').merge(
                         'observations' => result['observations'].size,
                         'numeric_valid' => result['observations'].count { |observation| observation['numeric_valid'] },
                         'attempts' => result.dig('acquisition', 'attempts')
                       ))
    abort 'CBBD acquisition incomplete; inspect private manifest' unless result['complete']
  rescue KeyError, ArgumentError => e
    abort "CBBD configuration error: #{e.class} (check required environment and explicit bounds)"
  end

  desc 'Replay a private CBBD run manifest offline without credentials or imports'
  task replay: :environment do
    result = Ingestion::Cbbd::Adapter.replay(manifest: ENV.fetch('MANIFEST'))
    puts JSON.generate(result.slice('run_id', 'bounds', 'complete', 'manifest').merge('observations' => result['observations'].size))
    abort 'CBBD replay remains incomplete; inspect private manifest' unless result['complete']
  end
end
