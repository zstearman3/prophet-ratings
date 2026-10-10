# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoachingReview do
  it 'allows an explicitly ready empty year before season preparation' do
    expect(described_class.create!(year: 2027, ready: true)).to be_ready
    expect(Season.count).to eq(0)
  end

  it 'requires pending candidates to be resolved' do
    candidate = CoachingChange.create!(effective_year: 2027)
    review = described_class.new(year: 2027, ready: true)
    expect(review.save).to be(false)
    candidate.update!(status: 'rejected')
    expect(review.save).to be(true)
  end

  it 'invalidates readiness on new candidates and changed decisions' do
    review = described_class.create!(year: 2027, ready: true)
    candidate = CoachingChange.create!(effective_year: 2027)
    expect(review.reload).not_to be_ready
    candidate.update!(status: 'rejected')
    review.update!(ready: true)
    candidate.save!
    expect(review.reload).to be_ready
    candidate.update!(status: 'pending')
    expect(review.reload).not_to be_ready
  end

  it 'requires a unique valid integer year and prevents changing its key' do
    review = described_class.create!(year: 2027)
    expect(described_class.new(year: 2027)).not_to be_valid
    expect(described_class.new(year: '2027.5')).not_to be_valid
    expect(described_class.new(year: 0)).not_to be_valid
    expect(review.update(year: 2028)).to be(false)
  end
end
