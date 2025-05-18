# == Schema Information
#
# Table name: conferences
#
#  id           :bigint           not null, primary key
#  abbreviation :string
#  name         :string           not null
#  slug         :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_conferences_on_name  (name)
#  index_conferences_on_slug  (slug)
#
FactoryBot.define do
  factory :conference do
    
  end
end
