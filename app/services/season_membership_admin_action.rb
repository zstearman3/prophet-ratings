# frozen_string_literal: true

# Dispatches the custom admin form operations; all mutations keep their service-level guards.
class SeasonMembershipAdminAction
  # A preview renders in place; completed writes redirect with a notice.
  Result = Data.define(:notice, :school)

  def initialize(season, reviewer:)
    @season = season
    @reviewer = reviewer
  end

  def call(attributes)
    school = attributes.fetch('school_import', {})
    return Result.new(notice: nil, school: SeasonSchoolImport.new(season).preview(school)) if attributes['operation'] == 'prepare_school'

    Result.new(notice: perform(attributes), school: nil)
  end

  private

  attr_reader :season, :reviewer

  def perform(attributes)
    case attributes['operation']
    when 'refresh', 'refresh_previous'
      refresh(attributes)
    when 'map_conferences', 'map_cbbd_identities'
      map_identities(attributes)
    when 'save_school'
      save_school(attributes)
    when 'approve', 'correct_memberships'
      apply_review(attributes)
    else
      raise ArgumentError, 'Choose an action using the review form buttons; your entered values have been retained.'
    end
  end

  def refresh(attributes)
    year = season.year
    SeasonMembershipReview.new(season).refresh(source_year: attributes['operation'] == 'refresh_previous' ? year - 1 : year)
    nil
  end

  def map_identities(attributes)
    mapping = attributes.fetch('mapping', {})
    if attributes['operation'] == 'map_cbbd_identities'
      SeasonCbbdIdentityMapping.new(season).call(mapping)
      'identities_mapped'
    else
      SeasonConferenceMapping.new(season).call(mapping)
      'mapped'
    end
  end

  def save_school(attributes)
    SeasonSchoolImport.new(season).save(attributes.fetch('school_import', {}))
    'school_saved'
  end

  def apply_review(attributes)
    submission = SeasonMembershipAdminSubmission.build(season.membership_proposal, attributes.fetch('review', {}))
    if attributes['operation'] == 'approve'
      SeasonMembershipReview.new(season).apply(submission, reviewer:)
      'approved'
    else
      SeasonConferenceCorrection.new(season).call(submission, reviewer:)
      'corrected'
    end
  end
end
