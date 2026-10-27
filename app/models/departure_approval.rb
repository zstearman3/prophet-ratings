# frozen_string_literal: true

# Retains who explicitly approved the exact signed proposal and when.
class DepartureApproval < ApplicationRecord
  belongs_to :departure_validation
  belongs_to :user, optional: true

  def readonly?
    persisted?
  end

  def seal
    JSON.parse(attributes.except('signature', 'updated_at').merge('certificate' => departure_validation.certificate).to_json)
  end

  def sign
    token = Departures::ValidationIntegrity.verifier.generate(seal, purpose: 'approval')
    query = ApplicationRecord.sanitize_sql_array(['UPDATE departure_approvals SET signature = ? WHERE id = ?', token, id])
    self.class.connection.execute(query)
    reload
  end

  def authenticate
    expected = Departures::ValidationIntegrity.verifier.verified(signature, purpose: 'approval')
    Departures::Contract.check!(expected == seal, 'Departure approval signature changed; revalidate')
    Departures::Contract.check!(document['decision'] == 'approved' && review_hash == Departures::Contract.digest(document),
                                'Require exact approved departure document')
  end
end
