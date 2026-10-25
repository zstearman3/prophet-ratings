# frozen_string_literal: true

require_relative 'content'
require_relative 'fixture_manifest'
require_relative 'comparison_fixture'
require_relative 'setup_phase'
require_relative 'evidence_fixture'
require_relative 'history_fixture'
require_relative 'cbbd_fixture'
require 'tmpdir'
require 'active_support/testing/time_helpers'

module OffseasonPerformance
  # Shares persisted record identities across bounded synthetic setup phases without copying artifacts.
  FixtureState = Struct.new(:content, :season, :prior, :model, :admin, :batch, :attempt, :departure, :cbbd, :teams, keyword_init: true)

  # Coordinates deterministic fixture phases; never executes inside a measured web/worker window.
  class Fixture
    include ActiveSupport::Testing::TimeHelpers

    PHASES = { 'base' => :build, 'cbbd' => :prepare_cbbd, 'compare' => :compare, 'verify' => :verify, 'finish' => :finish }.freeze
    attr_reader :state

    def initialize(scale:)
      @state = FixtureState.new(content: Content.new(scale:))
      @history = HistoryFixture.new(@state)
      @evidence = EvidenceFixture.new(@state)
      @source = CbbdFixture.new(@state)
    end

    def self.guard!
      config = ActiveRecord::Base.connection_db_config
      unless config.database == 'offseason_benchmark' && config.configuration_hash[:host] == 'db' &&
             File.read('/benchmark/owner').strip == ENV.fetch('BENCHMARK_OWNER')
        raise 'Refusing non-owned benchmark database'
      end
    end

    def call(phase:)
      Fixture.guard!
      operation = PHASES.fetch(phase) { raise ArgumentError, 'Invalid fixture phase' }
      travel_to(Time.iso8601(Content::TIME)) { public_send(operation) }
    end

    def build
      raise 'Fixture requires an empty schema' if Season.exists? || Team.exists? || User.exists?

      Fixture.initialize_records(@state)
      populate
      save_state
    end

    def self.initialize_records(state)
      state.model = RatingsConfigVersion.publish!
      state.season = Season.create!(year: 2026, start_date: '2025-11-01', end_date: '2026-04-10', average_efficiency: 100, average_pace: 68)
      state.prior = Season.create!(year: 2025, start_date: '2024-11-01', end_date: '2025-04-10', average_efficiency: 100, average_pace: 68)
      state.admin = User.create!(email: 'benchmark@example.test', password: 'SyntheticBenchmark!2026', admin: true)
    end

    def populate
      SetupPhase.call('teams') { @history.create_teams }
      prepare_evidence
      SetupPhase.call('history_and_legacy_priors') { @history.history }
    end

    def prepare_evidence
      SetupPhase.call('departures') { @evidence.departures }
      SetupPhase.call('recruiting') { @evidence.recruiting }
    end

    def prepare_cbbd
      restore
      SetupPhase.call('cbbd') { @source.call(@state.prior) }
      save_state
    end

    def compare
      restore
      Fixture.compare_fixture(@state.cbbd.id)
    end

    def self.compare_fixture(id)
      builder = SetupPhase.call('cbbd_builder') { ComparisonFixture.builder(id) }
      SetupPhase.call('cbbd_staged_comparison') { ComparisonFixture.persist(builder, id) }
    end

    def verify
      restore
      SetupPhase.call('cbbd_fresh_normal_verification') { @source.verify_comparison }
    end

    def finish
      restore
      Fixture.load_artifacts(@state)
      publication = SetupPhase.call('initial_preview') { initial_preview }
      write_manifest(publication)
    end

    def self.load_artifacts(state)
      state.attempt.reload
      state.departure.reload
    end

    def write_manifest(publication)
      result = SetupPhase.call('manifest') { FixtureManifest.new(@state).call(publication) }
      File.write('/benchmark/fixture.json', JSON.pretty_generate(result))
    end

    def initial_preview
      season = @state.season
      PreseasonPublication.select_model(season, @state.model)
      publication = PreseasonPublication.review!(season, reviewer: @state.admin, mode: 'initialize')
      Fixture.perform_preview(publication)
    end

    def self.perform_preview(publication)
      PreviewPreseasonJob.perform_now(publication.id)
      publication.reload
      verify_initial_preview(publication)
      publication
    end

    def self.verify_initial_preview(publication)
      raise "Initial preview failed: #{publication.error_message}" unless publication.status == 'review'
    end

    def save_state
      values = { 'owner' => ENV.fetch('BENCHMARK_OWNER'), 'season' => @state.season.id, 'prior' => @state.prior.id,
                 'model' => @state.model.id, 'admin' => @state.admin.id, 'batch' => @state.batch.id,
                 'attempt' => @state.attempt.id, 'departure' => @state.departure.id, 'cbbd' => @state.cbbd&.id }
      File.write('/benchmark/setup-state.json', JSON.generate(values))
    end

    def restore
      values = JSON.parse(File.read('/benchmark/setup-state.json'))
      Fixture.verify_owner(values)
      restore_seasons(values)
      restore_artifacts(values)
      @state.teams = Team.order(:id).to_a
    end

    def self.verify_owner(values)
      expected = ENV.fetch('BENCHMARK_OWNER')
      actual = values.fetch('owner')
      raise 'Foreign fixture checkpoint' unless actual == expected
    end

    def restore_seasons(values)
      @state.season = Season.find(values.fetch('season'))
      @state.prior = Season.find(values.fetch('prior'))
      @state.model = RatingsConfigVersion.find(values.fetch('model'))
      @state.admin = User.find(values.fetch('admin'))
    end

    def restore_artifacts(values)
      @state.batch = DepartureBatch.select(:id).find(values.fetch('batch'))
      @state.attempt = DepartureAcquisition.select(:id).find(values.fetch('attempt'))
      @state.departure = OffseasonInputRevision.select(:id).find(values.fetch('departure'))
      @state.cbbd = CbbdReviewRun.select(:id, :season_id).find_by(id: values.fetch('cbbd'))
    end
  end
end
