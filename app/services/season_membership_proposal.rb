# frozen_string_literal: true

# Captures source proposals without changing memberships or the approved roster.
class SeasonMembershipProposal
  def self.resolve(rows, provider)
    { 'cbbd' => CbbdMembershipMatch }.fetch(provider, ConferenceAlignmentMatch).resolve(rows)
  end

  def self.from_saved(season)
    proposal = season.membership_proposal
    new(season, source_year: proposal.fetch('source_year', season.year), provider: proposal.fetch('provider', 'sports_reference'))
  end

  # Serialize identity writes with the fingerprint read and subsequent review writes.
  # The fixed order also agrees with reconciliation's team-identity table lock.
  def self.lock_identities
    connection = ApplicationRecord.connection
    connection.execute("SET LOCAL lock_timeout = '3s'")
    connection.execute('LOCK TABLE seasons, team_external_identities, conference_external_identities IN SHARE ROW EXCLUSIVE MODE')
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def self.canonical(value)
    converter = method(:canonical)
    case value
    when Hash then value.sort.to_h.transform_values(&converter)
    when Array then value.map(&converter)
    else value
    end
  end

  def self.proposed_row(team, match, year)
    previous = memberships_at(team, year - 1)
    choice = match&.conference ? match.conference.id.to_s : 'unresolved'
    {
      'team_id' => team.id, 'school' => team.school, 'previous' => membership_label(previous),
      'current' => membership_label(memberships_at(team, year)),
      'proposed' => match&.conference&.name || 'Not resolved from source', 'choice' => choice,
      'changed' => previous.map(&:conference_id) != [choice.to_i],
      'note' => match ? match.suggestions.join('; ') : 'Absent from source: verify participation; absence does not prove a D1 departure.'
    }
  end

  def self.source_row(team, match, years)
    year = years.fetch(:target)
    proposed_row(team, match, year).merge('carried_forward' => years.fetch(:source) != year)
  end

  def self.build_rows(matches, years)
    by_team = matches.index_by { |match| match.team&.id }
    builder = self
    Team.includes(team_conferences: %i[conference start_season end_season]).order(:school).map do |team|
      builder.source_row(team, by_team[team.id], years)
    end
  end

  def self.issues(matches)
    matches.flat_map(&:suggestions).tally.map { |issue, count| count > 1 ? "#{issue} (#{count} schools)" : issue }
  end

  def self.membership_label(memberships)
    memberships.map { |membership| membership.conference.name }.join(', ').presence || 'No stored membership'
  end

  def self.memberships_at(team, year)
    team.team_conferences.select { |membership| membership.covers_year?(year) }
  end

  def self.validate_target_year(proposal, submission)
    return if proposal['source_year'] == proposal['target_year']
    return if submission['confirm_target_year'] == '1'

    raise ArgumentError, 'Confirm target-year verification of the unverified previous-season draft before approval.'
  end

  def initialize(season, source_year: season.year, **options)
    @season = season
    @provider = options[:provider].presence || ENV.fetch('GAME_SYNC_PROVIDER', 'sports_reference')
    @provider_options = options.fetch(:provider_options, {})
    @source_year = SeasonPreparer.parse_year(source_year)
    validate_source_year
  end

  def capture
    before = fingerprint
    call.merge('initial_fingerprint' => before)
  end

  def call
    return capture_directory if @provider == 'cbbd'

    scraper = Scraper::ConferenceStandingsScraper.new(year: source_year)
    source = scraper.call
    build(source, source_url: scraper.source_url, captured_at: Time.current.iso8601)
  end

  def rebuild(source_rows:, source_url:, **evidence)
    source = source_rows.map(&:symbolize_keys)
    captured_at, acquisition = evidence.values_at(:captured_at, :acquisition)
    build(source, source_url:, captured_at:).tap { |proposal| proposal['acquisition'] = acquisition if acquisition }
  end

  def build(source, source_url:, captured_at:)
    Scraper::ConferenceStandingsScraper.validate!(source) unless @provider == 'cbbd'
    builder = self.class
    matches = builder.resolve(source, @provider)
    {
      'provider' => @provider, 'version' => 1, 'source_year' => source_year, 'target_year' => season.year,
      'source_url' => source_url, 'captured_at' => captured_at,
      'fingerprint' => fingerprint, 'source_rows' => source.as_json,
      'issues' => builder.issues(matches), 'rows' => proposed_rows(matches)
    }
  end

  def fingerprint
    self.class.digest([
                        season.attributes.slice('year', 'start_date', 'end_date', 'participation_review'),
                        Team.order(:id).pluck(:id, :school, :url), TeamAlias.order(:id).pluck(:team_id, :value, :source),
                        Conference.order(:id).pluck(:id, :name, :slug, :abbreviation, :sports_reference_slugs),
                        TeamConference.order(:id).pluck(:id, :team_id, :conference_id, :start_season_id, :end_season_id),
                        Season.order(:id).pluck(:id, :year), season.team_seasons.order(:id).pluck(:team_id),
                        TeamExternalIdentity.order(:id).pluck(:provider, :external_id, :team_id),
                        ConferenceExternalIdentity.order(:id).pluck(:provider, :external_id, :conference_id)
                      ])
  end

  def reviewed(submission)
    proposal = reviewed_snapshot(submission)
    self.class.validate_target_year(proposal, submission)
    proposal
  end

  def reviewed_snapshot(submission)
    proposal = season.membership_proposal
    raise ArgumentError, 'Refresh proposals before approval.' if proposal.blank?

    validate_snapshot(proposal, submission)
    proposal
  end

  private

  attr_reader :season, :source_year

  def capture_directory
    source = Ingestion::Cbbd::MembershipDirectory.new(source_year:, **@provider_options).call
    build(source.fetch('source_rows'), **source.slice('source_url', 'captured_at').symbolize_keys)
      .merge('acquisition' => source.fetch('acquisition'))
  end

  def validate_source_year
    raise ArgumentError, 'Unsupported membership provider' unless %w[sports_reference cbbd].include?(@provider)

    year = season.year
    return if [year, year - 1].include?(source_year)

    raise ArgumentError, 'Choose the target season or its immediately preceding source year.'
  end

  def validate_snapshot(proposal, submission)
    validator = self.class
    raise ArgumentError, 'Proposal changed; reload and review again.' unless submission.fetch('proposal_key') == validator.digest(proposal)
    return if proposal.fetch('fingerprint') == fingerprint

    raise ArgumentError, 'Local roster, dates or memberships changed; refresh and review again.'
  end

  def proposed_rows(matches)
    self.class.build_rows(matches, { target: season.year, source: source_year })
  end
end
