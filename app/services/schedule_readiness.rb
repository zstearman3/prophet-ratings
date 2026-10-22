# frozen_string_literal: true

# Acquisition is evidence for review, never certification of publication or predictions.
class ScheduleReadiness
  def initialize(season)
    @season = season
  end

  def usable?
    season.games.scheduled.joins(:home_team_season, :away_team_season).exists?
  end

  def summary
    run = ScheduleRefreshRun.where(season:).order(id: :desc).first
    deferral = ScheduleDeferral.where(season:).order(id: :desc).first
    [schedule_summary,
     "Latest acquisition: #{run&.status || 'none'}.", deferral_summary(deferral)].compact.join(' ')
  end

  private

  attr_reader :season

  def schedule_summary
    return 'Usable schedule stored; publication and prediction readiness require review.' if usable?

    'No usable schedule stored; prediction readiness unresolved.'
  end

  def deferral_summary(deferral)
    return unless deferral

    [deferral.summary, usable? ? 'Schedule now available: reassessment needed.' : 'Prediction readiness deferred.'].join(' ')
  end
end
