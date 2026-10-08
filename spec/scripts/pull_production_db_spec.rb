# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'bin/pull-production-db', type: :task do
  def prepare_script(root, host)
    FileUtils.mkdir_p("#{root}/bin")
    FileUtils.cp(File.expand_path('../../bin/pull-production-db', __dir__), "#{root}/bin/pull-production-db")
    File.write("#{root}/bin/docker", <<~BASH)
      #!/bin/bash
      printf '%s\\n' "$*" >> "$CALL_LOG"
      if [[ "$1" == run ]]; then
        [[ "${FAIL_DECODE:-}" != 1 ]] || exit 1
        printf 'SET transaction_timeout = 0;\\nSET row_security = off;\\nSELECT 1;\\nSET transaction_timeout = 0;\\n'
      fi
    BASH
    File.write("#{root}/bin/compose", <<~BASH)
      #!/bin/bash
      printf '%s\\n' "$*" >> "$CALL_LOG"
      if [[ "$1" == ps ]]; then
        printf 'db\\nweb\\nworker\\n'
      elif [[ "$*" == *"exec -T db psql"* ]]; then
        cat > "$CALL_LOG.sql"
      fi
    BASH
    FileUtils.chmod(0o755, ["#{root}/bin/docker", "#{root}/bin/compose"])
    File.write("#{root}/.env.docker", "DATABASE_URL=postgresql://postgres:password@#{host}:5432/prophet_ratings_development\n")
  end

  def pull_environment(root, log)
    {
      'PATH' => "#{root}/bin:#{ENV.fetch('PATH')}",
      'CALL_LOG' => log,
      'LOCAL_DATABASE_URL' => nil,
      'DOTENV_FILE' => "#{root}/missing.env",
      'DOCKER_DOTENV_FILE' => "#{root}/.env.docker",
      'DUMP_FILE' => "#{root}/dump",
      'PRODUCTION_DATABASE_URL' => 'postgresql://source:password@production/example',
      'LOCAL_ADMIN_EMAIL' => 'admin@example.test',
      'LOCAL_ADMIN_PASSWORD' => 'test-password'
    }
  end

  ['localhost', '127.0.0.1', 'db'].each do |host|
    it "uses the db service for Rails and the database container URL for restore with #{host}" do
      Dir.mktmpdir('production-pull-spec') do |root|
        prepare_script(root, host)
        log = "#{root}/calls"
        env = pull_environment(root, log)
        output, status = Open3.capture2e(env, 'bash', "#{root}/bin/pull-production-db", '--source', 'direct', '--yes')
        expect(status.success?).to be(true), output
        calls = File.readlines(log)
        expect(calls.find { |call| call.start_with?('run --rm -i') }).to include('postgres:17-trixie pg_restore')
        rails_calls = calls.select { |call| call.include?('web bin/rails') }
        expect([rails_calls.size, rails_calls]).to match(
          [4, all(include('-e DATABASE_URL=postgresql://postgres:password@db:5432/prophet_ratings_development'))]
        )
        restore = calls.find { |call| call.include?('exec -T db psql') }
        restore_host = host == 'db' ? 'localhost' : host
        expect(File.read("#{log}.sql")).to eq("SET row_security = off;\nSELECT 1;\nSET transaction_timeout = 0;\n")
        expect(restore).to include(
          '--no-psqlrc --set ON_ERROR_STOP=1 --single-transaction',
          "--dbname postgresql://postgres:password@#{restore_host}:5432/prophet_ratings_development"
        )
      end
    end
  end

  it 'retains the dump and leaves services and the database untouched when decoding fails' do
    Dir.mktmpdir('production-pull-spec') do |root|
      prepare_script(root, 'db')
      log = "#{root}/calls"
      env = pull_environment(root, log).merge('FAIL_DECODE' => '1')
      output, status = Open3.capture2e(env, 'bash', "#{root}/bin/pull-production-db", '--source', 'direct', '--yes')
      expect(status.success?).to be(false)
      expect(File).to exist("#{root}/dump")
      expect(output).to include('dump retained')
      expect(File.read(log)).not_to include('stop web', 'stop worker', 'db:drop', 'exec -T db psql')
      expect(File).not_to exist("#{root}/dump.sql.raw")
    end
  end
end
