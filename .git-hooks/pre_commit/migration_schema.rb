# frozen_string_literal: true

module Overcommit
  module Hook
    module PreCommit
      class MigrationSchema < Base
        def run
          schema = all_files.find { |file| file.end_with?('/db/schema.rb') }
          migrations = applicable_files.grep(%r{/db/migrate/\d+_.*\.rb\z})
          instructions = 'Run bin/migrate, then review and stage db/schema.rb with your migrations.'

          if migrations.any? && applicable_files.none?(schema)
            return [:fail, "Migration changes need a staged db/schema.rb update. #{instructions}"]
          end

          latest_version = all_files.filter_map { |file| file[%r{/db/migrate/(\d+)_.*\.rb\z}, 1] }.max
          schema_version = File.read(schema)[/\.define\(version:\s*([\d_]+)/, 1]&.delete('_') if schema
          return :pass if schema_version && schema_version == latest_version

          [:fail, "db/schema.rb does not match the latest migration (#{latest_version}). #{instructions}"]
        end
      end
    end
  end
end
