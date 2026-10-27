# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ProphetRatings
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    # Dependency-generation and certificate integrity triggers are part of the schema.
    config.active_record.schema_format = :sql

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.action_controller.action_on_unpermitted_parameters = false

    # The app does not use Active Storage image variants.
    config.active_storage.variant_processor = :disabled

    config.active_job.queue_adapter = :good_job
    config.good_job.retry_on_unhandled_error = false
    unless Rails.env.test?
      # Web processes only enqueue, even if an inherited environment requests async.
      config.good_job.execution_mode = :external
      config.good_job.queues = ENV.fetch('GOOD_JOB_QUEUES', 'heavy:1;-heavy:1')
      config.good_job.poll_interval = ENV.fetch('GOOD_JOB_POLL_INTERVAL', '1').to_i
      config.good_job.subprocesses = ENV.fetch('GOOD_JOB_SUBPROCESSES', '0').to_i
      config.good_job.shutdown_timeout = ENV.fetch('GOOD_JOB_SHUTDOWN_TIMEOUT', '30').to_i
      config.good_job.enable_cron = false if Rails.env.development?
    end
  end
end
