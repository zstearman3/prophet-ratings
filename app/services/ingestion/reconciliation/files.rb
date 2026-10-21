# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Private operator files, replayed offline; reports are never overwritten.
    class Files
      def self.compare(manifest:, report:)
        replay = Cbbd::Adapter.replay(manifest:)
        season = Season.find_by!(year: replay.fetch('bounds').fetch('season'))
        comparison = Comparison.new(season:, replay:).call
        write_report(report, comparison)
        comparison.fetch('coverage').merge('report' => File.expand_path(report))
      end

      def self.write_report(path, comparison)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.pretty_generate(comparison)) }
      end

      def self.apply(manifest:, report:, decisions:)
        record = Apply.new(comparison: JSON.parse(File.read(report)), replay: Cbbd::Adapter.replay(manifest:),
                           decisions: JSON.parse(File.read(decisions))).call
        { 'decision_id' => record.id, 'mappings' => record.result.fetch('mappings').size }
      end
    end
  end
end
