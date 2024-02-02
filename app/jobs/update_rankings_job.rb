# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  queue_as :default

  def perform(season = Season.current)
    ProphetRatings::OverallRatingsCalculator.new(season).calculate_season_ratings
  end
end
