# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Saturated inclusive intervals split with overlap, then deduplicate by source ID.
    class BoundedRetriever
      ID_FIELDS = { '/games' => %w[id], '/games/teams' => %w[gameId teamId] }.freeze
      attr_reader :ledger

      def initialize(client:, bounds:, row_cap: 3000)
        raise ArgumentError, 'row cap must be positive' unless row_cap.positive?

        @client = client
        @bounds = bounds
        @row_cap = row_cap
        @ledger = { 'complete' => true, 'failures' => [], 'partitions' => [], 'selected_captures' => [],
                    'decisions' => [], 'initial_request_estimate' => 2 }
      end

      def call
        rows = Client::ENDPOINTS.index_with { |endpoint| endpoint_rows(endpoint) }
        ledger.merge!(attempt_summary)
        rows
      end

      def self.filters_for(endpoint, interval, season)
        { 'endpoint' => endpoint, 'season' => season,
          'startDateRange' => interval.begin.iso8601(3), 'endDateRange' => interval.end.iso8601(3) }
      end

      def self.identity(entry, fields)
        entry.fetch('raw').values_at(*fields)
      end

      private

      def attempt_summary
        attempts = @client.attempts
        captures = @client.captures
        { 'attempts' => attempts, 'captures' => captures,
          'retries' => attempts - ledger['partitions'].count { |partition| partition['capture_id'] },
          'latest_quota_headers' => captures.last&.fetch('headers') }
      end

      def endpoint_rows(endpoint)
        retained = {}
        retrieve(endpoint, @bounds.start_time..@bounds.end_time).each { |entry| retain_entry(retained, entry, ID_FIELDS.fetch(endpoint)) }
        retained.values
      end

      def retrieve(endpoint, interval)
        filters = self.class.filters_for(endpoint, interval, @bounds.season)
        result = @client.request(filters)
        partition = filters.merge('outcome' => result['outcome'], 'capture_id' => result.dig('capture', 'id'))
        ledger['partitions'] << partition
        partition_rows(result, partition, interval)
      end

      def partition_rows(result, partition, interval)
        outcome = result.fetch('outcome')
        return fail_partition(outcome, partition) unless outcome == 'success'
        return select_rows(result, partition) if result['rows'].length < @row_cap
        return fail_partition('saturated_minimum_interval', partition) if interval.end - interval.begin <= 1

        split(partition.fetch('endpoint'), interval)
      end

      def split(endpoint, interval)
        first = interval.begin
        last = interval.end
        midpoint = Time.at(Rational(((first.to_r + last.to_r) * 500).floor, 1000)).utc
        retrieve(endpoint, first..midpoint) + retrieve(endpoint, midpoint..last)
      end

      def select_rows(result, partition)
        reference = result.fetch('capture')
        ledger['selected_captures'] << reference['id']
        partition['selected'] = true
        result.fetch('rows').each_with_index.filter_map { |row, index| selected_entry(row, index, partition) }
      end

      def selected_entry(row, index, partition)
        error = SourceRowValidator.new(row, partition).call
        if error
          fail_partition(error, partition.merge('row_index' => index))
          return
        end
        { 'raw' => row,
          'provenance' => @client.captures.find { |capture| capture['id'] == partition['capture_id'] }.merge('row_index' => index) }
      end

      def retain_entry(retained, entry, fields)
        key = self.class.identity(entry, fields)
        previous = retained[key]
        return retained[key] = entry unless previous

        duplicate(previous, entry, key)
      end

      def duplicate(previous, entry, key)
        decision = { 'identity' => key, 'retained' => previous['provenance'], 'duplicate' => entry['provenance'],
                     'outcome' => previous['raw'] == entry['raw'] ? 'identical' : 'conflict' }
        ledger['decisions'] << decision
        fail_partition('conflicting_duplicate', decision) if decision['outcome'] == 'conflict'
      end

      def fail_partition(reason, evidence)
        ledger['complete'] = false
        ledger['failures'] << { 'reason' => reason, 'evidence' => evidence.dup }
        []
      end
    end
  end
end
