# frozen_string_literal: true

module Admin
  # Compact summaries keep decisions separate from the full retained evidence.
  module OffseasonReadinessReviewsHelper
    def readiness_badge(status)
      colors = { 'pass' => 'bg-green-100 text-green-800', 'deferred' => 'bg-gray-100 text-gray-700' }
      tag.span(status.humanize, class: "rounded px-2 py-1 text-xs font-semibold #{colors.fetch(status, 'bg-yellow-100 text-yellow-800')}")
    end

    def readiness_check_evidence(check, report)
      key, status, evidence = check.values_at('key', 'status', 'evidence')
      lines = if key == 'publication' && status == 'pass'
                ["#{report.fetch('teams').size} included teams; applied captures, core outputs and preopening ranks verified."]
              else
                Array.wrap(evidence)
              end
      safe_join(lines.map { |item| readiness_evidence_item(item) })
    end

    def readiness_evidence_item(item)
      return tag.li(item.to_s) unless item.is_a?(Hash)

      safe_join(item.map { |key, value| tag.li("#{key.humanize}: #{value.presence || 'Not recorded'}") })
    end
  end
end
