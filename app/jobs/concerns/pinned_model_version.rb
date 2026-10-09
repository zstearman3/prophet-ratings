# frozen_string_literal: true

# Pin before serialization; the same ID survives deserialization and ActiveJob retry.
module PinnedModelVersion
  extend ActiveSupport::Concern

  included do
    before_enqueue :pin_model_version
    before_perform :pin_model_version
  end

  private

  def pin_model_version
    last_argument = arguments.last
    options = if last_argument.is_a?(Hash)
                arguments.pop.dup
              else
                {}
              end
    options[:ratings_config_version_id] ||= RatingsConfigVersion.default_version.id
    arguments << Hash.ruby2_keywords_hash(options)
  end
end
