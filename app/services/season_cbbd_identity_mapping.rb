# frozen_string_literal: true

# Persist reviewed first-time matches without approving a roster or changing source data.
class SeasonCbbdIdentityMapping
  def self.rows(proposal)
    matches = CbbdMembershipMatch.resolve(proposal.fetch('source_rows').map(&:symbolize_keys))
    { 'teams' => matches.filter_map(&:pending_team),
      'conferences' => matches.filter_map(&:pending_conference).uniq { |row| row.fetch(:external_id) } }
  end

  def self.pending?(proposal)
    return false unless proposal['provider'] == 'cbbd'

    source = proposal.fetch('source_rows')
    teams = source.pluck('team_external_id') - TeamExternalIdentity.where(provider: 'cbbd').pluck(:external_id)
    conferences = source.pluck('conference_external_id') - ConferenceExternalIdentity.where(provider: 'cbbd').pluck(:external_id)
    teams.any? || conferences.any?
  end

  def initialize(season)
    @season = season
  end

  def call(submission)
    Season.with_ratings_lock do
      Season.transaction do
        SeasonMembershipProposal.lock_identities
        @season.with_lock { save(submission) }
      end
    end
  end

  private

  def save(submission)
    proposal = reviewed_proposal(submission)
    persist(selections_for(proposal, submission))
    self.class.validate_unique_teams(proposal)
    rebuild(proposal)
  end

  def reviewed_proposal(submission)
    raise ArgumentError, 'Refresh the saved CBBD directory before matching.' if @season.membership_proposal.blank?

    proposal = SeasonMembershipProposal.from_saved(@season).reviewed_snapshot(submission)
    raise ArgumentError, 'Choose a saved CBBD directory proposal.' unless proposal['provider'] == 'cbbd'

    proposal
  end

  def rebuild(proposal)
    builder = SeasonMembershipProposal.from_saved(@season)
    @season.update!(membership_proposal: builder.rebuild(**proposal.slice('source_rows', 'source_url', 'captured_at',
                                                                          'acquisition').symbolize_keys))
  end

  def selections_for(proposal, submission)
    mapper = self.class
    selections = mapper.rows(proposal).to_h do |kind, rows|
      [kind, mapper.selected_rows(rows, submission.fetch(kind, {}))]
    end
    raise ArgumentError, 'Choose at least one CBBD identity match.' if selections.values.all?(&:empty?)

    selections
  end

  public_class_method def self.selected_rows(rows, values)
    selected = values.compact_blank
    unless (selected.keys - rows.pluck(:external_id)).empty?
      raise ArgumentError, 'Unknown or already mapped CBBD source ID; reload the saved matches.'
    end

    selected
  end

  def persist(selections)
    mapper = self.class
    mapper.save_teams(selections.fetch('teams'))
    mapper.save_conferences(selections.fetch('conferences'))
  end

  public_class_method def self.save_teams(selections)
    selections.each do |external_id, local_id|
      TeamExternalIdentity.associate!(team: Team.find(local_id), provider: 'cbbd', external_id:)
    end
  end

  public_class_method def self.save_conferences(selections)
    selections.each do |external_id, local_id|
      ConferenceExternalIdentity.associate!(conference: Conference.find(local_id), provider: 'cbbd', external_id:)
    end
  end

  public_class_method def self.validate_unique_teams(proposal)
    source_ids = proposal.fetch('source_rows').pluck('team_external_id')
    duplicates = TeamExternalIdentity.where(provider: 'cbbd', external_id: source_ids).group(:team_id).having('COUNT(*) > 1')
    return unless duplicates.exists?

    raise ArgumentError, 'Multiple source IDs map to the same local school; review the selected matches.'
  end
end
