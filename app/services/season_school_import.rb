# frozen_string_literal: true

# Completes a source school's identity and target-season dependencies before roster approval.
class SeasonSchoolImport
  FIELDS = %w[school nickname short_name location home_venue primary_color].freeze

  def self.pending(season)
    source = season.membership_proposal.fetch('source_rows', []).map(&:symbolize_keys)
    ready_ids = ready_team_ids(season)
    ConferenceAlignmentMatch.resolve(source).zip(source).filter_map do |match, row|
      row.stringify_keys if awaiting_setup?(match, ready_ids)
    end
  end

  def self.awaiting_setup?(match, ready_ids)
    team = match.team
    match.teams.empty? || (team && ready_ids.exclude?(team.id))
  end

  def self.ready_team_ids(season)
    aliases = TeamAlias.where.not(value: [nil, '']).select(:team_id)
    TeamSeason.where(season:, team_id: aliases).pluck(:team_id).to_set
  end

  def self.resolved_team(source)
    ConferenceAlignmentMatch.resolve([source.symbolize_keys]).sole.team
  end

  def self.source_url(source)
    "/cbb/schools/#{source.fetch('team_slug')}/men/"
  end

  def self.persist_team(source, attributes)
    (resolved_team(source) || Team.new).tap do |team|
      team.assign_attributes(attributes.slice(*FIELDS).merge('url' => source_url(source)))
      team.save! if team.new_record? || team.changed?
    end
  end

  def initialize(season)
    @season = season
  end

  def preview(submission)
    source = source_row(submission)
    name = source.fetch('team_name')
    importer = self.class
    team = importer.resolved_team(source) || Team.new(school: name)
    { 'team_slug' => source.fetch('team_slug'), 'source_name' => name,
      'proposal_key' => submission.fetch('proposal_key'), 'attributes' => team.attributes.slice(*FIELDS),
      'url' => importer.source_url(source), 'existing' => team.persisted? }
  end

  def save(submission)
    Season.with_ratings_lock do
      season.with_lock { import(submission) }
    end
  end

  private

  attr_reader :season

  def source_row(submission)
    proposal = season.membership_proposal
    unless proposal.present? && submission['proposal_key'] == SeasonMembershipProposal.digest(proposal)
      raise ArgumentError, 'Proposal changed; reload and review the school import again.'
    end

    source = self.class.pending(season).find { |row| row.fetch('team_slug') == submission['team_slug'] }
    source || raise(ArgumentError, 'School is no longer awaiting setup in this proposal; reload and review again.')
  end

  def import(submission)
    source = source_row(submission)
    team = self.class.persist_team(source, submission.fetch('attributes', {}))
    Importer::Setup::BaseDataImporter.import_alias(team, source.fetch('team_name'))
    TeamSeason.find_or_create_by!(team:, season:)
    rebuild_proposal
  end

  def rebuild_proposal
    proposal = season.membership_proposal
    builder = SeasonMembershipProposal.new(season, source_year: proposal.fetch('source_year', season.year))
    season.update!(membership_proposal: builder.rebuild(**proposal.slice('source_rows', 'source_url', 'captured_at').symbolize_keys))
  end
end
