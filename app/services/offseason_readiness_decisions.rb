# frozen_string_literal: true

# Optional open work can be deferred, while missing data remains an explicit gap.
class OffseasonReadinessDecisions
  def initialize(report, acknowledge:, deferrals: {})
    @report = report
    @acknowledge = acknowledge
    @deferrals = deferrals.to_h.stringify_keys.compact_blank
  end

  def call
    validate_acknowledgement
    validate_deferrals
    { acknowledgement: acknowledgement, deferrals: deferrals }
  end

  private

  attr_reader :report, :acknowledge, :deferrals

  public_class_method def self.optional_open_keys(report)
    report.fetch('checks').select { |check| !check['hard'] && check['status'] == 'open' }.pluck('key')
  end

  def validate_acknowledgement
    return if report.fetch('gaps').empty? || acknowledge == '1'

    raise ArgumentError, 'Explicitly acknowledge the exact captured and current input gaps before saving this review.'
  end

  def acknowledgement
    gaps = report.fetch('gaps')
    gaps.present? ? { 'gaps' => gaps } : {}
  end

  def validate_deferrals
    allowed = self.class.optional_open_keys(report)
    raise ArgumentError, 'Only displayed optional open checks may be deferred.' unless (deferrals.keys - allowed).empty?
    return if deferrals.values.all? { |reason| reason.is_a?(String) && reason.strip.present? && reason.length <= 1000 }

    raise ArgumentError, 'Each deferral requires a reason of 1–1000 characters.'
  end
end
