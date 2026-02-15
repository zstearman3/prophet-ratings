# frozen_string_literal: true

class ChartDataBuilder
  PERCENTAGE_STATS = %w[
    adj_effective_fg_percentage
    adj_effective_fg_percentage_allowed
    adj_turnover_rate
    adj_turnover_rate_forced
    adj_free_throw_rate
    adj_free_throw_rate_allowed
    adj_three_pt_proficiency
    adj_defensive_rebound_rate
    adj_offensive_rebound_rate
  ].freeze

  def initialize(snapshots:, season:, selected_stat:)
    @snapshots = snapshots
    @season = season
    @stat = selected_stat.presence || 'rating'
  end

  def stat_title
    {
      'rating' => 'Rating',
      'adj_offensive_efficiency' => 'Adj ORtg',
      'adj_defensive_efficiency' => 'Adj DRtg',
      'adj_pace' => 'Adj Pace',
      'adj_three_pt_proficiency' => 'Adj 3PT Proficiency',
      'adj_defensive_rebound_rate' => 'Adj DRB Rate',
      'adj_offensive_rebound_rate' => 'Adj ORB Rate',
      'adj_effective_fg_percentage' => 'Adj eFG%',
      'adj_effective_fg_percentage_allowed' => 'Adj eFG% Allowed',
      'adj_turnover_rate' => 'Adj TO Rate',
      'adj_turnover_rate_forced' => 'Adj TO Rate Forced',
      'adj_free_throw_rate' => 'Adj FTR',
      'adj_free_throw_rate_allowed' => 'Adj FTR Allowed'
    }[@stat] || @stat.titleize
  end

  def percentage?
    PERCENTAGE_STATS.include?(@stat)
  end

  def chart_data
    raw = @snapshots.map { |s| [s.snapshot_date, s.send(@stat) || 0.0] }
    percentage? ? raw.map { |d| [d[0], (d[1] * 100.0).round(3)] } : raw
  end

  def reference_lines
    avg_attr = stat_to_avg_attr(@stat)
    stddev_attr = stat_to_stddev_attr(@stat)
    avg = season_average(avg_attr)
    stddev = season_std_dev(stddev_attr)

    avg *= 100 if percentage?
    stddev *= 100 if percentage?

    dates = chart_data.map(&:first)
    {
      avg: dates.map { |d| [d, avg] },
      upper: dates.map { |d| [d, avg + stddev] },
      lower: dates.map { |d| [d, avg - stddev] },
      upper2: dates.map { |d| [d, avg + (2.0 * stddev)] },
      lower2: dates.map { |d| [d, avg - (2.0 * stddev)] }
    }
  end

  private

  def season_average(avg_attr)
    return (@season.avg_adj_offensive_efficiency || 0).to_f - (@season.avg_adj_defensive_efficiency || 0).to_f if avg_attr == 'rating'

    @season.try(avg_attr) || 0
  end

  def season_std_dev(stddev_attr)
    return StatisticsUtils.stddev(@season.team_seasons.pluck(:rating)).round(3) if stddev_attr == 'rating'

    @season.try(stddev_attr) || 0
  end

  def stat_to_avg_attr(stat)
    {
      'rating' => 'rating',
      'adj_offensive_efficiency' => 'avg_adj_offensive_efficiency',
      'adj_defensive_efficiency' => 'avg_adj_defensive_efficiency',
      'adj_pace' => 'average_pace',
      'adj_three_pt_proficiency' => 'avg_adj_three_pt_proficiency',
      'adj_defensive_rebound_rate' => 'avg_adj_defensive_rebound_rate',
      'adj_offensive_rebound_rate' => 'avg_adj_offensive_rebound_rate',
      'adj_effective_fg_percentage' => 'avg_adj_effective_fg_percentage',
      'adj_effective_fg_percentage_allowed' => 'avg_adj_effective_fg_percentage_allowed',
      'adj_turnover_rate' => 'avg_adj_turnover_rate',
      'adj_turnover_rate_forced' => 'avg_adj_turnover_rate_forced',
      'adj_free_throw_rate' => 'avg_adj_free_throw_rate',
      'adj_free_throw_rate_allowed' => 'avg_adj_free_throw_rate_allowed'
    }[stat] || 'average'
  end

  def stat_to_stddev_attr(stat)
    {
      'rating' => 'rating',
      'adj_offensive_efficiency' => 'stddev_adj_offensive_efficiency',
      'adj_defensive_efficiency' => 'stddev_adj_defensive_efficiency',
      'adj_pace' => 'pace_std_deviation',
      'adj_three_pt_proficiency' => 'stddev_adj_three_pt_proficiency',
      'adj_defensive_rebound_rate' => 'stddev_adj_defensive_rebound_rate',
      'adj_offensive_rebound_rate' => 'stddev_adj_offensive_rebound_rate',
      'adj_effective_fg_percentage' => 'stddev_adj_effective_fg_percentage',
      'adj_effective_fg_percentage_allowed' => 'stddev_adj_effective_fg_percentage_allowed',
      'adj_turnover_rate' => 'stddev_adj_turnover_rate',
      'adj_turnover_rate_forced' => 'stddev_adj_turnover_rate_forced',
      'adj_free_throw_rate' => 'stddev_adj_free_throw_rate',
      'adj_free_throw_rate_allowed' => 'stddev_adj_free_throw_rate_allowed'
    }[stat] || 'std_deviation'
  end
end
