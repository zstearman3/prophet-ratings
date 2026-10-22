# frozen_string_literal: true

module Departures
  # Typed provider keys and historical URLs occupy separate namespaces.
  module PlayerIdentity
    def self.key(row)
      return Contract.url!(row.fetch('player_source_url')) unless row['provider']

      Contract.check!(row.fetch('provider') == 'cbbd', 'Unsupported player provider')
      id = Contract.integer!(row.fetch('provider_athlete_id'), 'CBBD athlete ID', minimum: 1)
      "cbbd/athlete/#{id}"
    end

    def self.production_key(row)
      row['provider'] ? row.fetch('production_key') : row.fetch('source_id')
    end

    def self.choice(table, player)
      "#{production_key(table)}|#{key(player)}"
    end

    def self.team_candidates(provider_id)
      return [] unless provider_id

      TeamExternalIdentity.where(provider: 'cbbd', external_id: provider_id.to_s).order(:team_id).pluck(:team_id).uniq
    end

    def self.validate_contract(dataset)
      schema = dataset['schema']
      if schema == CbbdDataset::VERSION
        Contract.check!(dataset.values_at('provider', 'extraction_version') == ['cbbd', CbbdDataset::EXTRACTION],
                        'Invalid CBBD dataset contract')
      else
        Contract.check!([nil, Contract::VERSION].include?(schema) && !dataset.key?('provider'), 'Invalid dataset contract')
      end
    end
  end
end
