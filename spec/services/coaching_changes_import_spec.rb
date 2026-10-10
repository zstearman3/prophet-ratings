# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoachingChangesImport do
  let(:rows) { JSON.parse(file_fixture('coaching_changes/rows.json').read).map { |row| row.fetch('value').symbolize_keys } }
  let(:scraper) { instance_double(Scraper::CoachingChangesScraper, call: rows) }
  let(:scraper_factory) { class_double(Scraper::CoachingChangesScraper, new: scraper) }
  let(:importer) { described_class.new(year: 2027, scraper: scraper_factory) }
  let!(:alpha) { create(:team, school: 'Alpha University') }
  let!(:beta) { create(:team, school: 'Beta University') }

  it 'proposes cross-row moves before Season preparation without asserting responsibility' do
    result = importer.call
    candidate = CoachingChange.find(result[:candidates].first[:candidate_id])
    expect(candidate).to have_attributes(team_id: alpha.id, previous_team_id: beta.id, status: 'pending',
                                         previous_year: nil, previous_role: nil, full_season_head_coach: false)
    expect(result).to include(d1_rows: 2, resolved_destinations: 2, unresolved_destinations: 0)
    expect(Season.count).to eq(0)
    expect(TeamOffseasonProfile.count).to eq(0)
  end

  it 'keeps identical retries unchanged and preserves readiness after manual review' do
    importer.call
    CoachingChange.find_each { |candidate| candidate.update!(status: 'rejected') }
    review = CoachingReview.create!(year: 2027, ready: true)
    timestamps = CoachingChange.pluck(:updated_at)
    expect { importer.call }.not_to change(CoachingChange, :count)
    expect(CoachingChange.pluck(:updated_at)).to eq(timestamps)
    expect(review.reload).to be_ready
  end

  it 'deduplicates a manual equivalent and preserves verified history and readiness' do
    candidate = CoachingChange.create!(effective_year: 2027, team: alpha, coach_name: 'shared coach', status: 'confirmed',
                                       previous_team: beta, previous_year: 2026, previous_role: 'head_coach', full_season_head_coach: true)
    CoachingChange.create!(effective_year: 2027, team: beta, coach_name: 'New Beta', status: 'rejected')
    review = CoachingReview.create!(year: 2027, ready: true)
    report = importer.call[:candidates].first
    expect(report[:candidate_id]).to eq(candidate.id)
    expect(report[:conflicts]).to be_empty
    expect(candidate.reload).to have_attributes(status: 'confirmed', previous_year: 2026, full_season_head_coach: true)
    expect(review.reload).to be_ready
  end

  it 'preserves reviewed decisions and reports changed facts, invalidating only on new input' do
    importer.call
    CoachingChange.find_each { |candidate| candidate.update!(status: 'confirmed') }
    candidate = CoachingChange.find_by!(team: alpha)
    review = CoachingReview.create!(year: 2027, ready: true)
    rows.first[:new_coach] = 'Changed Coach'
    report = importer.call[:candidates].first
    expect(report[:conflicts]).to include(coach_name: 'Changed Coach')
    expect(candidate.reload).to have_attributes(coach_name: 'Shared Coach', status: 'confirmed')
    expect(review.reload).not_to be_ready
    review.update!(ready: true)
    importer.call
    expect(review.reload).to be_ready
  end

  it 'invalidates readiness when the source former coach changes even without a direct move' do
    importer.call
    CoachingChange.find_each { |candidate| candidate.update!(status: 'rejected') }
    review = CoachingReview.create!(year: 2027, ready: true)
    rows.last[:old_coach] = 'Different Former Coach'
    importer.call
    expect(review.reload).not_to be_ready
    expect(CoachingChange.find_by!(team: alpha).status).to eq('rejected')
  end

  it 'updates pending proposals and clears unsupported history when the proposed coach changes' do
    importer.call
    candidate = CoachingChange.find_by!(team: alpha)
    candidate.update!(previous_year: 2026, previous_role: 'head_coach', full_season_head_coach: true)
    rows.first[:new_coach] = 'First Time Coach'
    importer.call
    expect(candidate.reload).to have_attributes(coach_name: 'First Time Coach', previous_team_id: nil, previous_year: nil,
                                                previous_role: nil, full_season_head_coach: false, status: 'pending')
  end

  it 'retains unresolved labels and ambiguous alias candidate IDs without creating teams' do
    create(:team_alias, team: beta, value: 'Alpha University', source: 'hoopdirt')
    rows.last[:school] = 'Unknown School'
    result = importer.call
    report = result[:candidates].first
    expect(report[:destination_team_ids]).to contain_exactly(alpha.id, beta.id)
    expect(result[:unresolved_destinations]).to eq(2)
    expect(CoachingChange.find(report[:candidate_id]).destination_school).to eq('Alpha University')
    expect(Team.count).to eq(2)
  end

  it 'reuses a reviewed alias and never silently reassigns ambiguous aliases' do
    rows.first[:school] = 'Alpha Alias'
    importer.call
    candidate = CoachingChange.find_by!(destination_school: 'Alpha Alias')
    expect(candidate.team_id).to be_nil
    create(:team_alias, team: alpha, value: 'Alpha Alias', source: 'hoopdirt')
    importer.call
    expect(candidate.reload.team_id).to eq(alpha.id)
    create(:team_alias, team: beta, value: 'Alpha Alias', source: 'other')
    importer.call
    expect(candidate.reload.team_id).to be_nil
    expect(TeamAlias.where(value: 'Alpha Alias').pluck(:team_id)).to contain_exactly(alpha.id, beta.id)
  end

  it 'retains multiple prior schools, interim and spelling variants for manual review' do
    rows << rows.last.merge(school: 'Unknown School', old_coach: 'Shared Coach', new_coach: 'New Interim (INTERIM)')
    result = importer.call
    expect(result[:candidates].first[:possible_previous_schools]).to contain_exactly('Beta University', 'Unknown School')
    expect(CoachingChange.find_by!(team: alpha).previous_team_id).to be_nil
    rows.first[:new_coach] = 'Shared-Coach'
    result = importer.call
    expect(result[:candidates].first[:possible_previous_schools]).to be_empty
    expect(result[:candidates].last[:source][:new_coach]).to eq('New Interim (INTERIM)')
  end

  it 'reports colliding manual equivalents and preserves them as separate review items' do
    2.times { CoachingChange.create!(effective_year: 2027, team: alpha, coach_name: 'Shared Coach', status: 'rejected') }
    result = importer.call
    report = result[:candidates].first
    expect(report[:equivalent_candidate_ids].size).to eq(2)
    expect(report[:conflicting_candidate_ids].size).to eq(2)
    expect(report[:status]).to eq('pending')
    expect { importer.call }.not_to change(CoachingChange, :count)
  end

  it 'invalidates a ready empty year on new pending candidates without marking it ready' do
    review = CoachingReview.create!(year: 2027, ready: true)
    importer.call
    expect(review.reload).not_to be_ready
    expect(CoachingChange.distinct.pluck(:status)).to eq(['pending'])
  end

  it 'rejects empty or malformed input before writes and preserves approved records' do
    candidate = CoachingChange.create!(effective_year: 2027, team: alpha, coach_name: 'Reviewed', status: 'confirmed')
    review = CoachingReview.create!(year: 2027, ready: true)
    rows.clear
    expect { importer.call }.to raise_error(Scraper::CoachingChangesScraper::Error, /empty/)
    expect(candidate.reload.status).to eq('confirmed')
    expect(review.reload).to be_ready
  end

  it 'invalidates readiness once when reviewed source identities change through aliases' do
    rows.first[:school] = 'Alpha Alias'
    mapping = create(:team_alias, team: alpha, value: 'Alpha Alias', source: 'hoopdirt')
    importer.call
    CoachingChange.find_each { |candidate| candidate.update!(status: 'confirmed') }
    review = CoachingReview.create!(year: 2027, ready: true)
    mapping.update!(team: beta)
    report = importer.call[:candidates].first
    expect(report[:conflicts]).to include(team_id: beta.id)
    expect(CoachingChange.find(report[:candidate_id]).team_id).to eq(alpha.id)
    expect(review.reload).not_to be_ready
    review.update!(ready: true)
    importer.call
    expect(review.reload).to be_ready
  end

  it 'invalidates readiness for newly resolved or ambiguous previous identities without overwriting reviewed facts' do
    rows.last[:school] = 'Beta Alias'
    importer.call
    CoachingChange.find_each { |candidate| candidate.update!(status: 'rejected') }
    review = CoachingReview.create!(year: 2027, ready: true)
    create(:team_alias, team: beta, value: 'Beta Alias', source: 'hoopdirt')
    report = importer.call[:candidates].first
    expect(report[:conflicts]).to include(previous_team_id: beta.id)
    expect(CoachingChange.find(report[:candidate_id]).previous_team_id).to be_nil
    expect(review.reload).not_to be_ready
    review.update!(ready: true)
    importer.call
    expect(review.reload).to be_ready
    create(:team_alias, team: alpha, value: 'Beta Alias', source: 'other')
    importer.call
    expect(review.reload).not_to be_ready
  end

  it 'reports source omissions without removing decisions and invalidates readiness once' do
    importer.call
    CoachingChange.find_each { |candidate| candidate.update!(status: 'rejected') }
    review = CoachingReview.create!(year: 2027, ready: true)
    omitted = rows.pop
    absent = CoachingChange.find_by!(team: beta)
    expect(importer.call[:absent_candidate_ids]).to eq([absent.id])
    expect(absent.reload).to have_attributes(status: 'rejected', discovery_present: false)
    expect(review.reload).not_to be_ready
    review.update!(ready: true)
    importer.call
    expect(review.reload).to be_ready
    rows << omitted
    importer.call
    expect(review.reload).not_to be_ready
  end

  it 'deduplicates unresolved schools across whitespace-only source changes' do
    rows.first[:school] = 'Unresolved School '
    importer.call
    original_id = CoachingChange.find_by!(discovery_school: 'unresolved school').id
    rows.first[:school] = ' unresolved school'
    result = importer.call
    expect(result[:candidates].first[:candidate_id]).to eq(original_id)
    expect(CoachingChange.count).to eq(2)
  end

  it 'rolls back all changes on a late persistence failure' do
    proposal = instance_double(CoachingChangeProposal)
    allow(CoachingChangeProposal).to receive(:new).and_wrap_original do |method, **args|
      args[:match].facts[:destination_school] == 'Beta University' ? proposal : method.call(**args)
    end
    allow(proposal).to receive(:call).and_raise(ActiveRecord::RecordInvalid)
    expect { importer.call }.to raise_error(ActiveRecord::RecordInvalid)
    expect(CoachingChange.count).to eq(0)
  end
end
