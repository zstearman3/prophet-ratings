# frozen_string_literal: true

# The signed-in admin's decisions supply provenance without requiring typed notes.
# Scripted reviews continue to use the underlying services' explicit evidence contract.
class SeasonMembershipAdminSubmission
  def self.build(proposal, attributes)
    rows = proposal.fetch('rows', []).index_by { |row| row.fetch('team_id').to_s }
    teams = attributes.fetch('teams', {}).to_h do |id, decision|
      [id, decision.merge('reason' => reason(rows[id], decision))]
    end
    attributes.merge('evidence' => 'Manual Review', 'teams' => teams)
  end

  def self.reason(row, decision)
    choice = decision['choice']
    return '' if row && choice == row['choice'] && choice != 'excluded'

    'Manual Review'
  end
end
