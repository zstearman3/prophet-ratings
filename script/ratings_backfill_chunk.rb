# frozen_string_literal: true

# Internal protocol for bin/backfill-ratings. Each invocation is a fresh Rails process.
$stdout.sync = true
$stderr.sync = true

begin
  request = JSON.parse(ENV.fetch('BACKFILL_REQUEST'))
  worker = ProphetRatings::ChunkedRatingsBackfill.new(request)
  case request.fetch('phase')
  when 'plan'
    puts "BACKFILL_PLAN #{worker.plan.to_json}"
  when 'run'
    worker.run
  else
    raise ArgumentError, 'Unknown backfill phase'
  end
rescue JSON::ParserError, KeyError, ArgumentError, TypeError, ActiveRecord::RecordNotFound, Season::OperationInProgress => error
  warn "[backfill] failed: #{error.message}"
  exit 1
end
