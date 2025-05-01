# frozen_string_literal: true

module StatsHelpers
  def expected_possessions(fga:, orb:, tov:, fta:)
    (fga - orb + tov + (0.475 * fta)).round(1)
  end

  def expected_turnover_rate(tov:, possessions:)
    return nil if possessions.zero?

    tov.to_f / possessions
  end

  def expected_true_shooting_percentage(pts:, fga:, fta:)
    denom = 2 * (fga + (0.44 * fta))
    return nil if denom.zero?

    pts / denom
  end

  def expected_effective_fg_percentage(fgm:, three_pm:, fga:)
    return nil if fga.zero?

    (fgm + (0.5 * three_pm)) / fga.to_f
  end
end
