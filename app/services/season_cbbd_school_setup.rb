# frozen_string_literal: true

# Explicit admin metadata completes a retained source school without fetching or approving a roster.
class SeasonCbbdSchoolSetup
  def initialize(season)
    @season = season
  end

  def preview(submission)
    source = source_row(submission)
    team = self.class.matched_team(source) || Team.new(school: source.fetch('team_name'))
    { 'team_external_id' => source.fetch('team_external_id'), 'proposal_key' => submission.fetch('proposal_key'),
      'existing' => team.persisted?, 'attributes' => team.attributes.slice(*SeasonSchoolImport::FIELDS, 'url') }
  end

  def save(submission)
    Season.with_ratings_lock { save_locked(submission) }
  rescue TeamExternalIdentity::Conflict => error
    raise ArgumentError, error.message
  end

  def self.school_attributes(attributes)
    attributes.slice(*SeasonSchoolImport::FIELDS, 'url').transform_values { |value| value.to_s.strip }.tap do |values|
      values['url'] = school_url(values['url'])
    end
  end

  def self.school_url(value)
    uri = URI.parse(value.to_s.strip)
    unless valid_school_uri?(uri)
      raise ArgumentError, 'Supply a verified Sports Reference school URL, such as /cbb/schools/school-name/men/.'
    end

    "#{uri.path.delete_suffix('/')}/"
  rescue URI::InvalidURIError
    raise ArgumentError, 'Supply a valid Sports Reference school URL.'
  end

  def self.valid_school_uri?(uri)
    host = uri.host.to_s.downcase
    relative_path = uri.relative? && host.empty?
    origin = relative_path || (uri.is_a?(URI::HTTPS) && %w[sports-reference.com www.sports-reference.com].include?(host))
    origin && !uri.userinfo && !uri.query && !uri.fragment && %r{\A/cbb/schools/[a-z0-9-]+/men/?\z}.match?(uri.path.to_s)
  end

  def self.matched_team(source)
    CbbdMembershipMatch.resolve([source.symbolize_keys]).sole.team
  end

  def self.validate_unique_school(team_id, attributes)
    name_conflict = Team.matching_school_or_alias(attributes['school']).where.not(id: team_id).exists?
    url_conflict = Team.where(url: attributes['url']).where.not(id: team_id).exists?
    return unless name_conflict || url_conflict

    raise ArgumentError, 'This school already exists; choose its existing CBBD match instead of creating another school.'
  end

  def self.save_alias(team, name)
    alias_record = TeamAlias.find_or_create_by!(value: name, source: 'cbbd') { |record| record.team = team }
    raise ArgumentError, 'CBBD alias already belongs to another school; review its match.' unless alias_record.team_id == team.id
  end

  def self.save_team(source, attributes)
    team = matched_team(source) || Team.new
    metadata = school_attributes(attributes)
    validate_unique_school(team.id, metadata)
    team.update!(metadata)
    team
  end

  private

  attr_reader :season

  def save_locked(submission)
    Season.transaction do
      SeasonMembershipProposal.lock_identities
      season.with_lock { import(submission) }
    end
  end

  def source_row(submission)
    proposal = SeasonMembershipProposal.from_saved(season).reviewed_snapshot(submission)
    raise ArgumentError, 'Choose a saved CBBD membership proposal.' unless proposal['provider'] == 'cbbd'

    SeasonSchoolImport.pending(season).find { |row| row.fetch('team_external_id') == submission['team_external_id'] } ||
      raise(ArgumentError, 'School is no longer awaiting setup in this proposal; reload and review again.')
  end

  def import(submission)
    source = source_row(submission)
    team = self.class.save_team(source, submission.fetch('attributes', {}))
    save_dependencies(team, source)
    rebuild_proposal
  end

  def save_dependencies(team, source)
    self.class.save_alias(team, source.fetch('team_name'))
    TeamSeason.find_or_create_by!(team:, season:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: source.fetch('team_external_id'))
    SeasonCbbdIdentityMapping.validate_unique_teams(season.membership_proposal)
  end

  def rebuild_proposal
    proposal = season.membership_proposal
    builder = SeasonMembershipProposal.from_saved(season)
    season.update!(membership_proposal: builder.rebuild(**proposal.slice('source_rows', 'source_url', 'captured_at',
                                                                         'acquisition').symbolize_keys))
  end
end
