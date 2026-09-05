# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include GoodJob::ActiveJobExtensions::InterruptErrors

  MAX_EXECUTIONS = 5

  retry_on StandardError, wait: :polynomially_longer, attempts: MAX_EXECUTIONS
end
