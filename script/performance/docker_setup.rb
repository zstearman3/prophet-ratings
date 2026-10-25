# frozen_string_literal: true

require 'benchmark'

module OffseasonPerformance
  # Builds the complete owned fixture and authenticates clients before any measured boot.
  class DockerSetup
    VERSIONS = 'ruby --version && bundle --version && python3 --version && ' \
               'python3 -c "import numpy; print(numpy.__version__)"'

    def initialize(run, result)
      @run = run
      @result = result
    end

    def call
      @result['setup_seconds'] = Benchmark.realtime { prepare_application }
      @result['runtime_versions'] = @run.compose('run', '--rm', '--no-deps', '-T', 'driver', 'bash', '-c', VERSIONS)
    end

    def prepare_application
      prepare_database
      @run.assets
      construct_fixture
      authenticate
    end

    def prepare_database
      @run.build_images
      @run.compose('up', '-d', '--wait', 'db')
      @run.compose('run', '--rm', '--no-deps', '-T', 'driver', 'bundle', 'exec', 'rails', 'db:schema:load')
    end

    def construct_fixture
      %w[base cbbd compare verify finish].each { |phase| setup_fixture(phase) }
      @result['fixture'] = JSON.parse(File.read(File.join(@run.directory, 'fixture.json')))
    end

    def setup_fixture(phase)
      state = @run.fixture_phase(phase)
      (@result['fixture_states'] ||= {})[phase] = state
      code = state.fetch('ExitCode')
      raise "Fixture setup failed: exit=#{code}, OOMKilled=#{state['OOMKilled']}; see commands.log" unless code.zero?
    end

    def authenticate
      @run.compose('up', '-d', 'web')
      @run.ready
      @run.compose('run', '--rm', '--no-deps', '-T', 'driver', 'bundle', 'exec', 'ruby', 'script/performance/driver.rb', 'auth')
    end
  end
end
