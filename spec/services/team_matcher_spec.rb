# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamMatcher do
  it 'preserves school precedence and normalized aliases with overlapping names' do
    school = create(:team, school: 'Synthetic Highland University')
    other = create(:team, school: 'Synthetic River College')
    school.team_aliases.create!(value: 'Highland Hoops')
    other.team_aliases.create!(value: school.school)
    matcher = described_class.new

    expect(matcher.match(school.school.downcase)).to eq(school)
    expect(matcher.match('HIGHLAND-HOOPS')).to eq(school)
  end

  it 'preserves the existing unmatched fuzzy fallback for a nonempty roster' do
    create(:team, school: 'Synthetic Highland University')
    expect(described_class.new.match('Synthetic Highland Universit')).to be_nil
  end
end
