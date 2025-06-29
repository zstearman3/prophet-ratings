# frozen_string_literal: true

# == Schema Information
#
# Table name: ratings_config_versions
#
#  id          :bigint           not null, primary key
#  config      :jsonb            not null
#  current     :boolean          default(FALSE)
#  description :string
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_ratings_config_versions_on_current  (current) UNIQUE WHERE (current IS TRUE)
#  index_ratings_config_versions_on_name     (name) UNIQUE
#
class RatingsConfigVersion < ApplicationRecord
  has_many :predictions, dependent: :nullify
  has_many :bet_recommendations, dependent: :nullify
  has_many :team_rating_snapshots, dependent: :nullify

  validates :config, presence: true
  validates :name, presence: true, uniqueness: true

  def self.current
    find_by(current: true)
  end

  def self.ensure_current!(config_hash = nil)
    config_hash ||= Rails.application.config_for(:ratings).deep_symbolize_keys

    transaction do
      update_all(current: false)
      find_or_create_by_config(config_hash).update!(current: true)
    end
  end

  def self.find_or_create_by_current_config
    current_config = Rails.application.config_for(:ratings).deep_symbolize_keys
    find_or_create_by_config(current_config)
  end

  def self.find_or_create_by_config(config_hash)
    config_json = config_hash.deep_stringify_keys
    existing = find_by(name: config_hash[:bundle_name])
    existing || create!(name: config_hash[:bundle_name], config: config_json)
  end
end
