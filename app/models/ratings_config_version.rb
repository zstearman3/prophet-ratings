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

  validate :preserve_model_identity
  validates :config, presence: true
  validates :name, presence: true, uniqueness: true

  def self.current
    find_by(current: true)
  end

  def self.ensure_current!(config_hash = nil)
    config_hash ||= Rails.application.config_for(:ratings).deep_symbolize_keys

    transaction do
      update_all(current: false)
      config = find_or_create_by_config(config_hash)
      config.update!(current: true)
      config
    end
  end

  def self.find_or_create_by_current_config
    current_config = Rails.application.config_for(:ratings).deep_symbolize_keys
    find_or_create_by_config(current_config)
  end

  def self.find_or_create_by_config(config_hash)
    config_json = config_hash.to_h.deep_stringify_keys
    existing = find_by(name: config_json.fetch('bundle_name'))
    if existing && existing.config != config_json
      raise ArgumentError, 'Ratings configuration changed under an existing bundle_name; use a new bundle_name'
    end

    existing || create!(name: config_json.fetch('bundle_name'), config: config_json)
  end

  private

  def preserve_model_identity
    return unless persisted? && (will_save_change_to_config? || will_save_change_to_name?)

    errors.add(:config, 'and name are immutable; create a new model version')
  end
end
