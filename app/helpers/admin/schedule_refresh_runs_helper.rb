# frozen_string_literal: true

module Admin
  # Plain-language summaries of retained import evidence, without raw source errors.
  module ScheduleRefreshRunsHelper
    ACQUISITION_ISSUES = {
      'transport' => 'The source could not be reached or returned an upstream error. Retry unfinished dates later.',
      'timeout' => 'The source took too long to respond. Retry unfinished dates later.',
      'quota' => 'The source request quota was reached. Wait for it to reset before retrying.',
      'request_budget' => 'The request budget was exhausted. Start a new run with a larger budget or a shorter date range.',
      'authentication' => 'The source rejected the API credentials. Check the worker credentials before retrying.',
      'authorization' => 'The source denied access. Check the API account permissions before retrying.',
      'malformed' => 'The source returned an unreadable response. Retry later; inspect retained evidence if this continues.',
      'saturated_minimum_interval' => 'Too many results for the smallest date range. Review retained acquisition details.',
      'conflicting_duplicate' => 'The source returned conflicting copies of a game. Review retained acquisition details.'
    }.freeze
    OUTCOME_LABELS = {
      'unmatched' => 'Teams need matching', 'ambiguous' => 'Ambiguous teams', 'invalid' => 'Invalid game stats',
      'conflict' => 'Conflicting data', 'incomplete' => 'Missing game data', 'protected' => 'Protected existing data',
      'stale' => 'Older source data', 'superseded' => 'Superseded game data'
    }.freeze

    def schedule_acquisition_issues(report)
      reasons = Array(report.dig('acquisition', 'failure_reasons'))
      messages = reasons.filter_map { |reason| ACQUISITION_ISSUES[reason] }.uniq
      tag.span(messages.join(' ')) if messages.any?
    end

    def schedule_day_problem(day)
      imported = day.fetch('imported_rows', 0)
      return tag.span("#{imported} game rows were committed; remaining games need review.") if imported.positive?
      return tag.span('Some games need review. No changes were saved for this date.') if day['rolled_back']
      if day.fetch('outcomes', {}).keys.intersect?(OUTCOME_LABELS.keys)
        return tag.span('Some games need review. No games were imported for this date.')
      end

      tag.span('The source could not be retrieved or imported. Check the import error and date details before retrying.')
    end

    def schedule_outcome_summary(day)
      labels = day.fetch('outcomes', {}).filter_map do |outcome, count|
        label = OUTCOME_LABELS[outcome]
        "#{label}: #{count}" if label && count.to_i.positive?
      end
      tag.span(labels.join(' · '))
    end

    def schedule_observation_matchup(observation)
      participants = observation.normalized_payload.values_at('home', 'away')
      tag.span(participants.map { |side| schedule_source_name(side.to_h['name']) }.join(' vs. '))
    end

    private

    def schedule_source_name(value)
      name = value.to_s
      return 'Team name unavailable' if name.match?(%r{\A\s*\z|https?://|(?:api[_-]?key|token|secret|password)\s*[=:]}i)

      truncate(name, length: 120)
    end
  end
end
