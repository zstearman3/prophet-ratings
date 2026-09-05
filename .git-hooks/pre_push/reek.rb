# frozen_string_literal: true

module Overcommit
  module Hook
    module PrePush
      class Reek < Base
        def run
          result = execute(command)
          return :pass if result.success?

          [:fail, result.stdout + result.stderr]
        end
      end
    end
  end
end
