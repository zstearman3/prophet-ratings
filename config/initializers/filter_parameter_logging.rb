# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
  passw secret token _key crypt salt certificate otp ssn
]

# Retained ingestion and ratings bodies can be tens of MB; avoid duplicating them in request and SQL logs.
Rails.application.config.filter_parameters << /\A(?:evidence|dataset|payload|inputs|report|stats|result)\z/
