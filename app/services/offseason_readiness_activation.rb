# frozen_string_literal: true

# Switch and successful audit commit together. Failed attempts are retained after rollback.
class OffseasonReadinessActivation
  def initialize(review, actor:, action:)
    @review = review
    @actor = actor
    @action = action
    raise ArgumentError, 'Choose season or model activation.' unless action.in?(%w[season model])
  end

  def call
    locked_attempt
  rescue StandardError => error
    record_failure(error)
    raise
  end

  private

  attr_reader :review, :actor, :action

  def locked_attempt
    OffseasonReadinessLock.new(review.season).call { review.with_lock { recorded_or_attempt } }
  end

  def recorded_or_attempt
    results = review.results
    results.key?(action) ? results.fetch(action) : attempt
  end

  def attempt
    review.class.transaction(requires_new: true) do
      review.verify_current
      before = OffseasonReadinessActivation.actual_ids
      switch
      save_success(before)
    end
  end

  def save_success(before)
    result = success_result(before)
    review.update!(results: review.results.merge(action => result))
    result
  end

  def success_result(before)
    after = OffseasonReadinessActivation.actual_ids
    { 'status' => before == after ? 'no_op' : 'succeeded', 'actor_id' => actor.id,
      'at' => Time.current.iso8601(6), 'previous' => before, 'resulting' => after }
  end

  def switch
    if action == 'season'
      review.season.set_current!
    else
      review.ratings_config_version.activate
    end
  end

  public_class_method def self.actual_ids
    { 'season_id' => Season.current&.id, 'model_id' => RatingsConfigVersion.published_default&.id }
  end

  def record_failure(error)
    review.with_lock do
      failure = { 'action' => action, 'status' => 'failed', 'actor_id' => actor.id, 'at' => Time.current.iso8601(6),
                  'error' => "#{error.class}: #{error.message}".truncate(2000), 'actual' => OffseasonReadinessActivation.actual_ids }
      review.update!(attempts: review.attempts + [failure])
    end
  end
end
