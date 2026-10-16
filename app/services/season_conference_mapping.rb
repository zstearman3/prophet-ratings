# frozen_string_literal: true

# Resolves source identities and rebuilds the saved proposal without fetching or approving memberships.
class SeasonConferenceMapping
  def self.unmatched(proposal)
    conferences = Conference.all.to_a
    proposal.fetch('source_rows', []).group_by { |row| row.fetch('conference_slug') }.filter_map do |slug, rows|
      unmatched_source(slug, rows, conferences)
    end
  end

  def self.unmatched_source(slug, rows, conferences)
    source = rows.first
    match = ConferenceAlignmentMatch.new(source.symbolize_keys, local_teams: [], local_conferences: conferences)
    { 'slug' => slug, 'name' => source.fetch('conference_name'), 'schools' => rows.size } if match.conferences.empty?
  end

  def initialize(season)
    @season = season
  end

  def call(submission)
    Season.with_ratings_lock do
      season.with_lock { save(submission) }
    end
  end

  private

  attr_reader :season

  def save(submission)
    proposal = saved_proposal(submission)
    Conference.order(:id).lock.load
    assign_mappings(proposal, submission.fetch('conferences', {}))
    builder = SeasonMembershipProposal.new(season, source_year: proposal.fetch('source_year', season.year))
    season.update!(membership_proposal: builder.rebuild(**proposal.slice('source_rows', 'source_url', 'captured_at').symbolize_keys))
  end

  def saved_proposal(submission)
    proposal = season.membership_proposal
    if proposal.blank? || submission['proposal_key'] != SeasonMembershipProposal.digest(proposal)
      raise ArgumentError, 'Proposal changed; reload and review conference mappings again.'
    end

    proposal
  end

  def assign_mappings(proposal, mappings)
    selected = mappings.compact_blank
    raise ArgumentError, 'Choose at least one conference mapping.' if selected.empty?

    available = self.class.unmatched(proposal).pluck('slug')
    selected.each { |slug, conference_id| assign_mapping(available, slug, conference_id) }
  end

  def assign_mapping(available, slug, conference_id)
    raise ArgumentError, "#{slug}: is no longer an unmatched source conference; reload and review again." unless available.include?(slug)

    Conference.find(conference_id).save_sports_reference_slug(slug)
  end
end
