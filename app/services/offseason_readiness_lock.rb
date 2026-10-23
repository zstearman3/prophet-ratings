# frozen_string_literal: true

# Uses existing writer coordination, with model serialization before reading default identity.
class OffseasonReadinessLock
  def initialize(season)
    @season = season
  end

  def call(&)
    Season.with_ratings_lock do
      @season.with_lock do
        RatingsConfigVersion.lock.order(:id).load
        CoachingReview.with_year_locks([@season.year], &)
      end
    end
  end
end
