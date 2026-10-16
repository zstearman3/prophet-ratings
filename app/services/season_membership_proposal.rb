# frozen_string_literal: true

# Captures source proposals without changing memberships or the approved roster.
class SeasonMembershipProposal
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

  def self.membership_label(memberships)
    memberships.map { |membership| membership.conference.name }.join(', ').presence || 'No stored membership'
  end

  def self.memberships_at(team, year)
    team.team_conferences.select do |membership|
      last_year = membership.end_season&.year
      membership.start_season.year <= year && (!last_year || last_year >= year)
    end
  end

  def initialize(season)
    @season = season
  end

  def capture
    before = fingerprint
    call.merge('initial_fingerprint' => before)
  end

  def call
    scraper = Scraper::ConferenceStandingsScraper.new(year: season.year)
    source = scraper.call
    Scraper::ConferenceStandingsScraper.validate!(source)
    matches = ConferenceAlignmentMatch.resolve(source)
    {
      'source_url' => scraper.source_url, 'captured_at' => Time.current.iso8601,
      'fingerprint' => fingerprint, 'source_rows' => source.as_json,
      'issues' => matches.flat_map(&:suggestions), 'rows' => proposed_rows(matches)
    }
  end

  def fingerprint
    self.class.digest([
                        season.attributes.slice('year', 'start_date', 'end_date', 'participation_review'),
                        Team.order(:id).pluck(:id, :school, :url), TeamAlias.order(:id).pluck(:team_id, :value, :source),
                        Conference.order(:id).pluck(:id, :name, :slug, :abbreviation),
                        TeamConference.order(:id).pluck(:id, :team_id, :conference_id, :start_season_id, :end_season_id),
                        Season.order(:id).pluck(:id, :year), season.team_seasons.order(:id).pluck(:team_id)
                      ])
  end

  private

  attr_reader :season

  def proposed_rows(matches)
    by_team = matches.index_by { |match| match.team&.id }
    builder = self.class
    Team.includes(team_conferences: %i[conference start_season end_season]).order(:school).map do |team|
      builder.proposed_row(team, by_team[team.id], season.year)
    end
  end
end
