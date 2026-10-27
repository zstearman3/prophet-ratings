# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DepartureProgress do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:membership) { create(:team_season, team:, season:) }
  let(:batch) { legacy_departure_batch(season) }

  before do
    membership
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    approve_departures(batch)
  end

  def certify_history
    operation = Departures::ValidationPreparation.create(batch.reload)
    PrepareDepartureValidationJob.perform_now(operation.id)
    expect(operation.reload.status).to eq('ready'), operation.error
    operation
  end

  def frozen_history
    [batch.reload.attributes, batch.revision.reload.attributes,
     membership.team_offseason_profile.reload.attributes, batch.acquisitions.order(:id).map(&:attributes),
     OffseasonInputRevision.count, DepartureApproval.count]
  end

  def prohibit_replay
    allow(Departures::RetainedEvidence).to receive(:new).and_raise('Public progress must not replay evidence')
    allow(Departures::ValidationEvidence).to receive(:new).and_raise('Public progress must not authenticate raw sources')
    allow(Dir).to receive(:mktmpdir).and_raise('Public progress must not create temporary files')
    allow(PrepareDepartureValidationJob).to receive(:perform_later).and_raise('Public progress must not queue validation')
    allow(PublishDepartureValidationJob).to receive(:perform_later).and_raise('Public progress must not queue publication')
  end

  def observe_reads(&)
    queries = []
    subscriber = ->(*, event) { queries << event.slice(:sql, :cached) if event[:sql].start_with?('SELECT') }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
    queries
  end

  it 'leaves an uncertified historical publication visibly needing review without replaying or queuing work' do
    history = frozen_history
    prohibit_replay
    expect do
      progress = described_class.new(season).call
      expect(progress.status).to eq('needs_review')
      expect(progress.last_result).to include("Departure revision ##{batch.revision_id} is retained.",
                                              'published; acquisition completed; validation needed.')
    end.not_to change(DepartureValidation, :count)
    expect(frozen_history).to eq(history)
  end

  it 'becomes complete only after the background validator certifies the unchanged historical revision and audit' do
    history = frozen_history
    expect(described_class.new(season).call.status).to eq('needs_review')
    operation = certify_history
    expect(operation.choices).to include('historical_revision_id' => batch.revision_id,
                                         'historical_input_hash' => batch.revision.input_hash)
    prohibit_replay
    expect(described_class.new(season).call.status).to eq('complete')
    expect(frozen_history).to eq(history)
  end

  it 'reads only scalar revision identity and acquisition status without caching payloads or source bodies', :aggregate_failures do
    certify_history
    prohibit_replay
    queries = observe_reads do
      ApplicationRecord.cache do
        2.times { expect(described_class.new(season).call.status).to eq('complete') }
      end
    end
    revision_reads = queries.select { |event| event[:sql].include?('FROM "offseason_input_revisions"') }
    acquisition_reads = queries.select { |event| event[:sql].include?('FROM "departure_acquisitions"') }
    expect(revision_reads).not_to be_empty
    expect(revision_reads.map { |event| event[:sql].split(' FROM ').first }.uniq).to eq(
      ['SELECT "offseason_input_revisions"."id", "offseason_input_revisions"."input_hash"']
    )
    expect(acquisition_reads.map { |event| event[:sql].split(' FROM ').first }.uniq).to eq(
      ['SELECT "departure_acquisitions"."status"']
    )
    expect(queries.pluck(:sql).join).not_to match(/\b(payload|evidence|manifest|dataset)\b/i)
    generations = queries.select { |event| event[:sql].include?('FROM departure_dependency_generations') }
    expect(generations.size).to eq(2)
    expect(generations.pluck(:cached)).not_to include(true)
  end

  it 'invalidates a previously complete certificate when a published profile pointer changes' do
    certify_history
    expect(described_class.new(season).call.status).to eq('complete')
    membership.team_offseason_profile.update!(departure_revision: nil)
    prohibit_replay
    progress = described_class.new(season).call
    expect(progress.status).to eq('needs_review')
    expect(progress.last_result).to include('acquisition completed; validation ready.')
  end

  it 'does not let a surrounding query cache hide identity invalidation of a previously complete certificate' do
    operation = certify_history
    prohibit_replay
    ApplicationRecord.cache do
      expect(described_class.new(season).call.status).to eq('complete')
      team.update!(school: 'Changed canonical identity')
      expect(operation.reload).not_to be_current
      expect(described_class.new(season).call.status).to eq('needs_review')
    end
  end
end
