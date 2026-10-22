# frozen_string_literal: true

# Unknown evidence remains distinct from observed zero and from a disabled coefficient.
class PreseasonPublicationGaps
  def initialize(entry)
    @entry = entry
  end

  def call
    reasons = inputs['contract'] == 'preseason-v3-reviewed-efficiency' ? reviewed_gaps : legacy_gaps
    reasons.compact.map { |kind, reason| gap(kind, reason) }
  end

  private

  attr_reader :entry

  def inputs
    entry.fetch('inputs')
  end

  def gap(kind, reason)
    { 'team_id' => entry.fetch('team_id'), 'team_name' => entry.fetch('team_name'), 'kind' => kind, 'reason' => reason }
  end

  def reviewed_gaps
    [recruiting_gap, departure_gap]
  end

  def recruiting_gap
    ['recruiting', 'Missing class points; contribution fallback is not verified zero.'] if
      entry.dig('efficiency', 'recruiting', 'class_points').blank?
  end

  def departure_gap
    ['departures', entry.dig('efficiency', 'departures', 'coverage', 'reason')] if
      entry.dig('efficiency', 'departures', 'coverage', 'loss_share').blank?
  end

  def legacy_gaps
    [(['recruiting', 'Missing legacy recruiting score; zero adjustment is a fallback.'] if
        inputs.dig('profile_values', 'recruiting_score').blank?),
     (['departures', 'Missing returning minutes fraction; zero attrition is a fallback.'] if
        inputs.dig('profile_values', 'returning_minutes_pct').blank?)]
  end
end
