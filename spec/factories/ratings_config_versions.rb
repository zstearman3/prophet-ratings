# frozen_string_literal: true

# == Schema Information
#
# Table name: ratings_config_versions
#
#  id          :bigint           not null, primary key
#  config      :jsonb            not null
#  description :string
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_ratings_config_versions_on_name  (name) UNIQUE
#
FactoryBot.define do
  factory :ratings_config_version do
    sequence(:name) { |n| "bundle_#{n}" }
    config { { bundle_name: name, sample: true } }
    created_at { Time.zone.now }
    updated_at { Time.zone.now }
  end
end
