# frozen_string_literal: true

# Parsed source values are retained independently of editable team mapping/exclusion decisions.
class RecruitingEntry < ApplicationRecord
  belongs_to :recruiting_batch
  belongs_to :team, optional: true
  validates :row_number, uniqueness: { scope: :recruiting_batch_id }
  attr_readonly :row_number, :source_label, :provider_team_id, :source_url, :source_rank,
                :class_points, :average_rating, :commit_count, :source_row, :source_errors

  def self.source_attributes(row)
    source = row.fetch('raw')
    raw = source.is_a?(Hash) ? source : {}
    values = row.fetch('values', {})
    { row_number: row.fetch('row_number'), source_row: source, source_errors: row.fetch('errors'),
      source_label: raw['team_label'], provider_team_id: raw['provider_team_id'], source_url: raw['team_url'],
      source_rank: values['rank'], class_points: values['class_points'], average_rating: values['average_rating'],
      commit_count: values['commit_count'], team_id: row['team_id'] }
  end

  def save_mapping(attributes)
    assign_mapping(attributes.fetch('team_id'))
    validate_external_identity

    save!
  end

  def assign_mapping(choice)
    self.excluded = choice == 'excluded'
    self.team_id = excluded? ? nil : choice.presence
  end

  def validate_external_identity
    raise ArgumentError, 'Conflicting durable CBBD identity' if Recruiting::CbbdIdentities.conflict?(source_row, team_id)
  end

  def associate_external_identity
    return unless Recruiting::Row.cbbd?(source_row)

    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: provider_team_id)
  end

  def review_row
    { 'row_number' => row_number, 'raw' => source_row, 'errors' => source_errors, 'values' => point_values,
      'team_id' => team_id, 'candidate_team_ids' => [team_id].compact, 'excluded' => excluded?, 'exclusions' => exclusions }
  end

  def point_values
    { 'rank' => source_rank, 'class_points' => class_points, 'average_rating' => average_rating,
      'commit_count' => commit_count }.transform_values { |value| value&.to_s('F') }
  end

  def exclusions
    errors = Recruiting::Row.review_errors('raw' => source_row, 'errors' => source_errors, 'excluded' => excluded?)
    return errors + ['Excluded by manual review'] if excluded?

    errors + (team_id ? [] : ['Choose a team or explicitly exclude this row'])
  end
end
