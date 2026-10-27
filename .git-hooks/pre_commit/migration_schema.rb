# frozen_string_literal: true

module Overcommit
  module Hook
    module PreCommit
      class MigrationSchema < Base
        def run
          schema = all_files.find { |file| file.end_with?('/db/structure.sql') }
          migrations = applicable_files.grep(%r{/db/migrate/\d+_.*\.rb\z})
          instructions = 'Run bin/migrate, then review and stage db/structure.sql with your migrations.'

          if migrations.any? && applicable_files.none?(schema)
            return [:fail, "Migration changes need a staged db/structure.sql update. #{instructions}"]
          end

          latest_version = all_files.filter_map { |file| file[%r{/db/migrate/(\d+)_.*\.rb\z}, 1] }.max
          ledger = File.read(schema)[/INSERT INTO (?:public\.)?"?schema_migrations"? \(version\) VALUES(.*?);/m, 1] if schema
          schema_version = ledger.to_s.scan(/\('(\d{14})'\)/).flatten.max
          return :pass if schema_version && schema_version == latest_version

          [:fail, "db/structure.sql does not match the latest migration (#{latest_version}). #{instructions}"]
        end
      end
    end
  end
end
