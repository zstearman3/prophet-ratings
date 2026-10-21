# frozen_string_literal: true

# Resolves source identities and rebuilds the saved proposal without fetching or approving memberships.
class SeasonConferenceMapping
  def self.unmatched(proposal)
    return unmatched_cbbd(proposal) if proposal['provider'] == 'cbbd'

    conferences = Conference.all.to_a
    proposal.fetch('source_rows', []).group_by { |row| row.fetch('conference_slug') }.filter_map do |slug, rows|
      unmatched_source(slug, rows, conferences)
    end
  end

  def self.unmatched_cbbd(proposal)
    mapped = ConferenceExternalIdentity.where(provider: 'cbbd').pluck(:external_id)
    proposal.fetch('source_rows').group_by { |row| row.fetch('conference_external_id') }.filter_map do |id, rows|
      { 'slug' => id, 'name' => rows.first.fetch('conference_name'), 'schools' => rows.size } unless mapped.include?(id)
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
      Season.transaction do
        SeasonMembershipProposal.lock_identities
        season.with_lock { save(submission) }
      end
    end
  end

  private

  attr_reader :season

  def save(submission)
    proposal = saved_proposal(submission)
    Conference.order(:id).lock.load
    assign_mappings(proposal, submission.fetch('conferences', {}))
    builder = SeasonMembershipProposal.from_saved(season)
    season.update!(membership_proposal: builder.rebuild(**proposal.slice('source_rows', 'source_url', 'captured_at',
                                                                         'acquisition').symbolize_keys))
  end

  def saved_proposal(submission)
    proposal = season.membership_proposal
    if proposal.blank? || submission['proposal_key'] != SeasonMembershipProposal.digest(proposal)
      raise ArgumentError, 'Proposal changed; reload and review conference mappings again.'
    end

    unless proposal.fetch('fingerprint') == SeasonMembershipProposal.new(season).fingerprint
      raise ArgumentError, 'Local roster, dates or memberships changed; refresh and review again.'
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

    conference = Conference.find(conference_id)
    if season.membership_proposal['provider'] == 'cbbd'
      ConferenceExternalIdentity.associate!(conference:, provider: 'cbbd', external_id: slug)
    else
      conference.save_sports_reference_slug(slug)
    end
  end
end
