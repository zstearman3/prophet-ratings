# frozen_string_literal: true

# Pin before enqueue and before HeavyJob can reschedule a direct perform_now.
class ScheduledGameSyncJob < HeavyJob
  before_enqueue :pin_scope
  before_perform :pin_scope, prepend: true

  def initialize(*arguments)
    super
    @provider = nil
    @run_id = nil
  end

  def perform(provider = nil, run_id = nil)
    @provider = provider
    @run_id = run_id
    dispatch
  end

  private

  def dispatch
    return SyncNightlyGamesJob.perform_later(provider: 'sports_reference') if @provider == 'sports_reference'
    return unless @run_id

    run = CbbdSyncRun.find(@run_id)
    Ingestion::Cbbd::ScheduledSync.new(run).call
    run.enqueue_analytics
  end

  def pin_scope
    return if arguments.any?

    provider = ENV.fetch('GAME_SYNC_PROVIDER', 'sports_reference')
    raise ArgumentError, 'Unsupported game sync provider' unless %w[cbbd sports_reference].include?(provider)

    self.arguments = [provider, provider == 'cbbd' ? CbbdSyncRun.pin_current&.id : nil]
  end
end
