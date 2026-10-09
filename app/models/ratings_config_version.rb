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
    config_hash ||= authored_config

    publish!(config_hash).activate
  end

  def self.authored_config
    application = Rails.application
    application.config_for(:ratings).to_h.deep_symbolize_keys.merge(
      contract_version: 1,
      prediction: application.config_for(:prediction).to_h.deep_symbolize_keys,
      defaults: application.config_for(:defaults).to_h.deep_symbolize_keys
    )
  end

  def self.publish!(payload = authored_config)
    ProphetRatings::ModelConfiguration.settings(new(name: payload[:bundle_name] || payload['bundle_name'], config: payload))
    find_or_create_by_config(payload)
  end

  def self.default_version
    published_default || raise(ArgumentError, 'No published default model version; publish and activate a model first')
  end

  def self.published_default
    current || find_by(name: Rails.application.config_for(:ratings).bundle_name)
  end

  def self.resolve(version = nil)
    return default_version unless version

    version.is_a?(RatingsConfigVersion) ? version : find(version)
  end

  def settings
    unless persisted? && !will_save_change_to_config? && !will_save_change_to_name?
      raise ArgumentError, 'Calculations require an unchanged persisted model version'
    end

    @settings ||= ProphetRatings::ModelConfiguration.settings(self)
  end

  def activate
    settings
    model = self.class
    model.transaction { model.activate_record(self) }
    self
  end

  def self.activate_record(version)
    lock.order(:id).load
    update_all(current: false)
    version.reload.update!(current: true)
  end

  def self.find_or_create_by_current_config
    publish!
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
