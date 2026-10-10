# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoachingChange do
  let(:team) { create(:team) }
  let(:facts) { { team: team, effective_year: 2027, coach_name: 'Synthetic Coach', status: 'confirmed' } }

  it 'stores unresolved pending candidates before seasons exist' do
    candidate = described_class.create!(effective_year: 2027, destination_school: 'Unresolved U')
    expect(candidate.status).to eq('pending')
    expect(Season.count).to eq(0)
  end

  it 'requires resolved identity to confirm but no evidence fields' do
    expect(described_class.new(effective_year: 2027, status: 'confirmed')).not_to be_valid
    expect(described_class.create!(facts)).to be_confirmed
  end

  it 'accepts four-digit positive integer years and rejects malformed years' do
    [1, 9999].each { |year| expect(described_class.new(effective_year: year)).to be_valid }
    [nil, 0, -1, 10_000, '2027.5', 'bad'].each do |year|
      expect(described_class.new(effective_year: year)).not_to be_valid
    end
  end

  it 'requires coherent full-season head-coach history' do
    candidate = described_class.new(facts.merge(full_season_head_coach: true))
    expect(candidate).not_to be_valid
    candidate.assign_attributes(previous_team: create(:team), previous_year: 2026, previous_role: 'head_coach')
    expect(candidate).to be_valid
    candidate.previous_role = 'assistant'
    expect(candidate).not_to be_valid
    candidate.previous_role = 'interim'
    expect(candidate).not_to be_valid
  end

  it 'allows confirmed first-time and assistant hires without full-season assertions' do
    expect(described_class.new(facts)).to be_valid
    expect(described_class.new(facts.merge(previous_role: 'assistant'))).to be_valid
    expect(described_class.new(facts.merge(previous_role: 'invented'))).not_to be_valid
  end

  it 'rejects invalid or nonpreceding previous years' do
    [0, 10_000, '2026.5', 2027, 2028].each do |year|
      expect(described_class.new(facts.merge(previous_year: year))).not_to be_valid
    end
  end

  it 'preserves proposals but prevents duplicate confirmed destinations at both layers' do
    described_class.create!(facts)
    expect(described_class.create!(facts.merge(status: 'pending'))).to be_persisted
    duplicate = described_class.create!(facts.merge(status: 'rejected'))
    expect(duplicate.update(status: 'confirmed')).to be(false)
    expect { duplicate.tap { |record| record.status = 'confirmed' }.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'requires explicit reconfirmation for corrected confirmed facts' do
    change = described_class.create!(facts)
    expect(change.update(coach_name: 'Corrected Coach')).to be(false)
    expect(change.errors.full_messages.join).to include('explicitly reconfirm')
    expect(change.update(reconfirm: true)).to be(true)
    expect(change.reconfirm).to be(false)
    expect(change.update(coach_name: 'Another correction')).to be(false)
  end

  it 'preserves confirmed and rejected decisions when imports repeat or conflict' do
    change = described_class.create!(facts)
    review = CoachingReview.create!(year: 2027, ready: true)
    expect(change.apply_imported_facts(coach_name: 'Synthetic Coach')).to be(true)
    expect(review.reload).to be_ready
    expect(change.apply_imported_facts(coach_name: 'Imported Correction')).to be(false)
    expect(change.reload.coach_name).to eq('Synthetic Coach')
    change.update!(status: 'rejected')
    expect(change.apply_imported_facts(coach_name: 'Imported Correction')).to be(false)
  end

  it 'only imports pending facts and cannot import review transitions' do
    change = described_class.create!(effective_year: 2027)
    expect(change.apply_imported_facts(coach_name: 'Synthetic Coach')).to be(true)
    expect(change.reload.status).to eq('pending')
    expect { change.apply_imported_facts(status: 'confirmed') }.to raise_error(ArgumentError)
  end

  it 'reports a changed year on a stale imported candidate without overwriting it' do
    stale = described_class.create!(effective_year: 2027)
    described_class.find(stale.id).update!(effective_year: 2028)
    expect(stale.apply_imported_facts(coach_name: 'Imported Coach')).to be(false)
    expect(stale.errors.full_messages.join).to include('reload and retry')
    expect(stale.reload.effective_year).to eq(2028)
    expect(stale.coach_name).to be_nil
  end

  it 'leaves the persisted candidate unchanged when imported facts fail validation' do
    change = described_class.create!(effective_year: 2027)
    expect(change.apply_imported_facts(previous_year: 2028)).to be(false)
    expect(change.errors[:previous_year]).to include('must precede the effective year')
    expect(change.reload.previous_year).to be_nil
    expect(CoachingReview.find_by(year: 2027)).to be_nil
  end

  it 'prevents stale edits from bypassing a newer confirmation decision' do
    stale = described_class.create!(effective_year: 2027, team: team, coach_name: 'Synthetic Coach')
    described_class.find(stale.id).update!(status: 'confirmed')
    review = CoachingReview.create!(year: 2027, ready: true)
    expect(stale.update(coach_name: 'Stale Correction')).to be(false)
    expect(stale.errors.full_messages.join).to include('reload and review')
    expect(review.reload).to be_ready
    expect(stale.reload.coach_name).to eq('Synthetic Coach')
  end

  it 'prevents stale saves and deletes from missing readiness for a moved year' do
    stale = described_class.create!(facts)
    described_class.find(stale.id).update!(effective_year: 2028, reconfirm: true)
    review = CoachingReview.create!(year: 2028, ready: true)
    expect(stale.update(coach_name: 'Stale Correction', reconfirm: true)).to be(false)
    expect { stale.destroy! }.to raise_error(ActiveRecord::RecordInvalid, /reload and review/)
    expect(review.reload).to be_ready
    expect(stale.reload.effective_year).to eq(2028)
  end

  it 'allows returning corrected facts to pending for later confirmation' do
    change = described_class.create!(facts)
    expect(change.update(coach_name: 'Corrected Coach', status: 'pending')).to be(true)
    expect(change.update(status: 'confirmed')).to be(true)
  end

  it 'preserves readiness on unchanged saves and invalidates it on corrections and deletion' do
    change = described_class.create!(facts)
    review = CoachingReview.create!(year: 2027, ready: true)
    change.save!
    expect(review.reload).to be_ready
    change.update!(coach_name: 'Corrected Coach', reconfirm: true)
    expect(review.reload).not_to be_ready
    review.update!(ready: true)
    change.destroy!
    expect(review.reload).not_to be_ready
  end

  it 'invalidates only the current year when deleting the same instance after moving it' do
    change = described_class.create!(facts)
    old_review = CoachingReview.create!(year: 2027)
    new_review = CoachingReview.create!(year: 2028)
    change.update!(effective_year: 2028, reconfirm: true)
    old_review.update!(ready: true)
    new_review.update!(ready: true)

    change.destroy!

    expect(old_review.reload).to be_ready
    expect(new_review.reload).not_to be_ready
  end

  it 'invalidates both source and destination review years when moving a candidate' do
    change = described_class.create!(facts)
    old_review = CoachingReview.create!(year: 2027, ready: true)
    new_review = CoachingReview.create!(year: 2028, ready: true)
    change.update!(effective_year: 2028, reconfirm: true)
    expect(old_review.reload).not_to be_ready
    expect(new_review.reload).not_to be_ready
  end
end
