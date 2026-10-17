# frozen_string_literal: true

require_relative 'notes'
require_relative 'repository'
require_relative 'version'

module ReleaseTool
  # Build all notes before remote writes; only an existing draft may move its tag.
  class Draft
    def initialize(options, repository: Repository)
      @options = options
      @repository = repository
      @plan = {}
    end

    def call
      ReleaseTool.capture('gh', 'auth', 'status')
      fetch_branches
      prepare
      display
      publish unless @options[:dry_run]
    end

    private

    def fetch_branches
      $stdout.puts 'Fetching origin/main and origin/development...'
      @repository.fetch
    end

    def prepare
      @plan = metadata
      prepare_notes
      validate_update if @options[:update]
      @plan[:previous_tag] = @repository.validate_tag(@plan)
    end

    def metadata
      branches = { target: @repository.sha('development'), base: @repository.sha('main') }
      branches.merge(repo: ReleaseTool.json('gh', 'repo', 'view', '--json', 'nameWithOwner').fetch('nameWithOwner'),
                     version: Version.new(@repository.tags, date: @options.fetch(:date)).choose(@options), update: @options[:update])
    end

    def prepare_notes
      commits = @repository.commits(@plan.fetch(:base), @plan.fetch(:target))
      raise Error, 'No commits to release between origin/main and origin/development.' if commits.empty?

      $stdout.puts "Building release notes for #{commits.size} commits..."
      @plan[:notes] = Notes.new(@plan.fetch(:repo)).render(@plan.merge(commits:))
    end

    def display
      $stdout.puts @plan.fetch(:notes)
      $stdout.puts "Dry run: no tags or releases changed (#{@plan.fetch(:version)})." if @options[:dry_run]
      $stdout.puts 'Notion status enrichment requires NOTION_TOKEN; ticket links are retained.' if ENV['NOTION_TOKEN'].to_s.empty?
    end

    def validate_update
      version = @plan.fetch(:version)
      info = ReleaseTool.json('gh', 'release', 'view', version, '--repo', @plan.fetch(:repo), '--json', 'isDraft')
      raise Error, "Refusing to change #{version}: the release is already published." unless info.fetch('isDraft')
    end

    def publish
      write_release
      @repository.push_tag(@plan)
      $stdout.puts "Draft #{@plan.fetch(:version)} prepared from #{@plan.fetch(:target)}. Review it on GitHub."
      $stdout.puts 'Deployment still requires promoting development to main; this script does not merge or deploy.'
    end

    def write_release
      Tempfile.create(['prophet-release-', '.md']) do |file|
        file.write(@plan.fetch(:notes))
        file.flush
        ReleaseTool.capture(*release_command, '--repo', @plan.fetch(:repo), '--target', @plan.fetch(:target),
                            '--title', "Release #{@plan.fetch(:version)}", '--notes-file', file.path)
      end
    end

    def release_command
      version = @plan.fetch(:version)
      @options[:update] ? ['gh', 'release', 'edit', version] : ['gh', 'release', 'create', version, '--draft']
    end
  end
end
