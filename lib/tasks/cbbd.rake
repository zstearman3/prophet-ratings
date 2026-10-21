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

namespace :cbbd do
  desc 'Compare a bounded offline replay to local identities; create a private review report'
  task compare: :environment do
    puts JSON.generate(Ingestion::Reconciliation::Files.compare(manifest: ENV.fetch('MANIFEST'), report: ENV.fetch('REPORT')))
  rescue KeyError, ArgumentError, ActiveRecord::RecordNotFound, Errno::EEXIST, Errno::ENOENT => e
    abort "CBBD comparison rejected: #{e.message}"
  end

  desc 'Apply explicit reviewed identity mappings only (no canonical game/stat refresh)'
  task apply_mappings: :environment do
    puts JSON.generate(Ingestion::Reconciliation::Files.apply(manifest: ENV.fetch('MANIFEST'), report: ENV.fetch('REPORT'),
                                                              decisions: ENV.fetch('DECISIONS')))
  rescue KeyError, ArgumentError, ActiveRecord::ActiveRecordError, TeamExternalIdentity::Conflict,
         GameExternalIdentity::Conflict, Ingestion::Reconciliation::Apply::RetryableConflict, Errno::ENOENT => e
    abort "CBBD mappings rejected: #{e.message}"
  end
end
