# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Persisted admin departure review' do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { legacy_departure_batch(season) }

  before do
    create(:team_season, season:, team:)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    sign_in admin
  end

  def prepared
    operation = Departures::ValidationPreparation.create(batch)
    PrepareDepartureValidationJob.perform_now(operation.id)
    operation.reload
  end

  def forbid_replay
    allow(Departures::RetainedEvidence).to receive(:new).and_raise('web replay forbidden')
    allow(Departures::SourceSnapshot).to receive(:new).and_raise('web parsing forbidden')
    allow(Dir).to receive(:mktmpdir).and_raise('web temporary replay forbidden')
  end

  it 'shows an explicit validation action without replaying or queuing work during GETs' do
    forbid_replay
    expect { get admin_departure_batch_path(batch) }.not_to change(DepartureValidation, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Validation needed', 'Validate retained evidence')
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    post revalidate_admin_departure_batch_path(batch)
    expect(PrepareDepartureValidationJob).to have_received(:perform_later).with(kind_of(Integer))
    expect([DepartureApproval.count, OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0, 0])
    get progress_admin_departure_batch_path(batch)
    expect(response.parsed_body.fetch('status')).to eq('queued')
  end

  it 'renders the saved all-pick report and queues exact actor approval without publishing in the request' do
    operation = prepared
    forbid_replay
    get admin_departure_batch_path(batch)
    expect(response.body).to include('Pick 60', 'Alpha, Alex', '0.25', 'Review saved choices')
    allow(PublishDepartureValidationJob).to receive(:perform_later)
    patch publish_admin_departure_batch_path(batch),
          params: { review: { review_key: operation.id.to_s, confirm: '1', reviewed_by: 'forged' } }
    expect(response).to have_http_status(:redirect)
    approval = DepartureApproval.last
    expect(approval).to have_attributes(user_id: admin.id, reviewed_by: admin.email)
    expect(approval.document.fetch('reviewed_at')).to eq(approval.reviewed_at.iso8601(6))
    expect(approval.document.fetch('decisions')).to eq(batch.decisions)
    expect(PublishDepartureValidationJob).to have_received(:perform_later).with(approval.id)
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count, batch.reload.status]).to eq([0, 0, 'draft'])
  end

  it 'formats repeated review labels once per request while retaining every team, pick and evidence link', :aggregate_failures do
    create_list(:team_season, 364, season:)
    operation = prepared
    report = operation.report
    values = (report.fetch('selections').pluck('status') + report.fetch('teams').pluck('reason')).uniq
    labels = values.index_with { |value| value.to_s.humanize }
    calls = Hash.new(0)
    allow(ActiveSupport::Inflector).to receive(:humanize).and_wrap_original do |method, value, **options|
      calls[value] += 1 if labels.key?(value)
      method.call(value, **options)
    end
    forbid_replay
    get admin_departure_batch_path(batch)
    first = response.body
    expect(calls).to eq(values.index_with { 1 })
    get admin_departure_batch_path(batch)
    expect(calls).to eq(values.index_with { 2 })
    expect(response.body).to eq(first)
    cells = response.parsed_body.css('[data-coverage-reason]')
    expect(cells.length).to eq(365)
    expect(cells.map(&:text)).to eq(report.fetch('teams').map { |row| labels.fetch(row.fetch('reason')) })
    expect(response.body).to include('Pick 60', 'Alpha, Alex', '0.25', 'Edit player choices', 'Download retained source',
                                     'review[review_key]', 'recovery[source_id]')
  end

  it 'rejects stale approval and displays corrupt legacy evidence as a durable failure with no replay fallback' do
    operation = prepared
    overwrite_departure_record(team, school: 'Changed School')
    patch publish_admin_departure_batch_path(batch), params: { review: { review_key: operation.id.to_s, confirm: '1' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(DepartureApproval.count).to eq(0)
    attempt = batch.attempt
    evidence = attempt.evidence.merge('source-1' => { 'snapshot_base64' => Base64.strict_encode64('corrupt') })
    overwrite_departure_record(attempt, evidence:)
    failed = prepared
    expect(failed.status).to eq('failed')
    forbid_replay
    get admin_departure_batch_path(batch)
    expect(response.body).to include('Validation failed', 'hash mismatch', 'Validate retained evidence')
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'never deserializes an annual plan, manifest or header during review and progress requests' do
    operation = prepared
    source = batch.plan.fetch('sources').last
    sources = Array.new(251) { |index| source.merge('id' => "large-#{index}", 'archival_annotation' => 'x' * 8192) }
    overwrite_departure_record(batch, plan: batch.plan.merge('sources' => sources))
    overwrite_departure_record(batch.attempt, manifest: batch.attempt.manifest.merge('sources' => sources))
    reads = []
    trace = TracePoint.new(:call) do |point|
      next unless point.defined_class == ActiveRecord::Type::Json && point.method_id == :deserialize

      value = point.binding.local_variable_get(:value)
      reads << value.bytesize if value.is_a?(String) && value.bytesize > 1024 * 1024
    end
    forbid_replay
    trace.enable do
      get admin_departure_batch_path(batch)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Validation stale', 'Next sources')
      get progress_admin_departure_batch_path(batch)
      expect(response.parsed_body.fetch('status')).to eq('stale')
      expect(DepartureProgress.new(season).call.status).to eq('needs_review')
    end
    expect(reads).to be_empty
    expect(operation.reload.status).to eq('ready')
  ensure
    trace&.disable
  end

  it 'quotes source IDs and player search input instead of treating submitted text as SQL' do
    prepared
    forbid_replay
    get admin_departure_batch_path(batch), params: { selection_key: '2025/1', player_search: "%' OR true; DROP TABLE teams; --" }
    expect(response).to have_http_status(:ok)
    get source_admin_departure_batch_path(batch), params: { attempt_id: batch.attempt.id, source_id: "x'; DROP TABLE teams; --" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Team.exists?(team.id)).to be(true)
  end

  it 'queues revalidation without loading annual acquisition JSON through required associations', :aggregate_failures do
    original = batch.attempt
    overwrite_departure_record(original, manifest: original.manifest.merge('annotation' => 'm' * (2 * 1024 * 1024)),
                                         evidence: original.evidence.merge('annotation' => 'e' * (2 * 1024 * 1024)))
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    queries = []
    reads = []
    observer = lambda do |_name, _start, _finish, _id, payload|
      queries << payload.fetch(:sql) if payload.fetch(:sql).include?('SELECT "departure_acquisitions".*')
    end
    trace = TracePoint.new(:call) do |point|
      next unless point.method_id == :instantiate_instance_of && point.binding.local_variable_defined?(:attributes)

      attributes = point.binding.local_variable_get(:attributes)
      bytes = %w[manifest dataset evidence].sum { |key| attributes[key].is_a?(String) ? attributes[key].bytesize : 0 }
      reads << bytes if bytes > 1024 * 1024
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') do
      trace.enable { post revalidate_admin_departure_batch_path(batch) }
    end
    expect(response).to have_http_status(:redirect)
    expect(DepartureValidation.last.status).to eq('queued')
    expect(queries).to be_empty
    expect(reads).to be_empty
  ensure
    trace&.disable
  end

  it 'keeps failed manual choices editable from captured rows and validates a corrected selection', :aggregate_failures do
    operation = prepared
    key = batch.decisions.first.fetch('selection_key')
    fields = { 'status' => 'eligible_prior_season', 'reason' => 'Review captured participation',
               'evidence_source_ids' => batch.decisions.first.fetch('evidence_source_ids'), 'stints' => {} }
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    Departures::DecisionEditor.new(batch, operation.id.to_s).save('rows' => { key => fields })
    failed = DepartureValidation.order(:id).last
    PrepareDepartureValidationJob.perform_now(failed.id)
    expect(failed.reload).to have_attributes(status: 'failed', error: 'Eligible selection requires production stints')
    forbid_replay
    get admin_departure_batch_path(batch)
    expect(response.body).to include('Validation failed', 'Edit player choices', 'selection_key=2025%2F1')
    get admin_departure_batch_path(batch), params: { selection_key: key }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Captured school player')
    fields['status'] = 'unknown_participation'
    patch admin_departure_batch_path(batch), params: { review: { review_key: failed.id.to_s, rows: { key => fields } } }
    expect(response).to have_http_status(:redirect)
    allow(Departures::RetainedEvidence).to receive(:new).and_call_original
    allow(Departures::SourceSnapshot).to receive(:new).and_call_original
    allow(Dir).to receive(:mktmpdir).and_call_original
    fresh = DepartureValidation.order(:id).last
    PrepareDepartureValidationJob.perform_now(fresh.id)
    expect(fresh.reload.status).to eq('ready'), fresh.error
    expect([DepartureApproval.count, OffseasonInputRevision.count]).to eq([0, 0])
  end

  it 'retains a recovered source in a successor and validates all bytes before making its fresh dataset ready' do
    prepared
    original = batch.attempt
    previous = original.attributes.deep_dup
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    upload = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/departures/school.html'), 'text/html')
    fields = { source_id: 'source-2', url: departure_fields.dig('sources', '1', 'url'), http_status: '200', html: upload,
               captured_at: '2026-10-21T10:00:00Z', observed_at: '2026-10-21T10:00:00Z', source_as_of_reason: 'Unavailable' }
    post recover_admin_departure_batch_path(batch), params: { recovery: fields }
    expect(response).to have_http_status(:redirect)
    successor = batch.reload.attempt
    expect(successor.predecessor_id).to eq(original.id)
    expect(successor.dataset.fetch('storage_version')).to eq(Departures::BatchSuccessor::PENDING)
    expect(batch.decisions).to be_empty
    operation = DepartureValidation.order(:id).last
    PrepareDepartureValidationJob.perform_now(operation.id)
    expect(operation.reload.status).to eq('ready'), operation.error
    expect(operation).to be_current
    expect(successor.reload.dataset.fetch('storage_version')).to eq(Departures::StoredDataset::VERSION)
    expect(original.reload.attributes).to eq(previous)
    expect([DepartureApproval.count, OffseasonInputRevision.count]).to eq([0, 0])
  end
end
