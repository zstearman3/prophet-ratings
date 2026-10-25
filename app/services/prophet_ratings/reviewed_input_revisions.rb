# frozen_string_literal: true

module ProphetRatings
  # Operation-local identity map: annual payloads are immutable and shared by many profiles.
  class ReviewedInputRevisions
    def initialize
      @records = {}
      @validated = {}
      @departures = {}
      @pending_bindings = {}
    end

    def self.approval(review)
      review.slice('review_status', 'approval', 'decision', 'reviewed_by', 'reviewed_at', 'version', 'reason',
                   'dataset_revision', 'mapping_revision')
    end

    def self.compact_evidence(evidence)
      return unless evidence

      evidence.merge('review' => approval(evidence.fetch('review')))
    end

    def self.compact_inputs(inputs)
      return inputs unless inputs.key?('reviewed_departures') || inputs.key?('reviewed_recruiting')

      inputs.merge('reviewed_departures' => DepartureContributionEvidence.compact(inputs['reviewed_departures']),
                   'reviewed_recruiting' => compact_evidence(inputs['reviewed_recruiting']))
    end

    def bind(profile)
      return unless profile

      %i[recruiting_revision departure_revision].each do |name|
        bind_revision(profile, name)
      end
      profile
    end

    def bind_revision(profile, name)
      revision = find_revision(profile, name)
      association = profile.association(name)
      association.target = revision
      remember_binding(revision, association)
    end
    private :bind_revision

    def remember_binding(revision, association)
      return unless revision

      id = revision.id
      (@pending_bindings[id] ||= []) << association unless @validated[id]
    end
    private :remember_binding

    def find_revision(profile, name)
      id = profile["#{name}_id"]
      @records.fetch(id) { @records[id] = OffseasonInputRevision.uncached { OffseasonInputRevision.find(id) } } if id
    end
    private :find_revision

    def validate(revision)
      id = revision.id
      @validated.fetch(id) do
        self.class.validate_full_revision(revision)
        release_payload(revision)
        @validated[id] = true
      end
    end

    def self.validate_full_revision(revision)
      OffseasonInputRevision.uncached { ReviewedEfficiencyInputs.validate_revision(revision) }
    end

    def release_payload(revision)
      id = revision.id
      @departures[id] = DepartureContributionEvidence.capture(revision) if revision.kind == 'departures'
      @records[id] = self.class.validated_projection(revision)
      @pending_bindings.delete(id)&.each { |association| association.target = @records.fetch(id) }
    end
    private :release_payload

    # Validation covers the full immutable source first. This operation-local view keeps only profile operands.
    def self.validated_projection(revision)
      payload = revision.payload
      retained = { 'team_inputs' => payload.fetch('team_inputs'), 'review' => approval(payload.fetch('review')) }
      OffseasonInputRevision.instantiate(revision.attributes.except('payload').merge('payload' => retained))
    end

    def departures(revision)
      id = revision.id
      @departures.fetch(id) { @departures[id] = DepartureContributionEvidence.capture(revision) }
    end
  end
end
