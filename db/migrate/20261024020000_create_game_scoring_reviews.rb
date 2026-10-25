# frozen_string_literal: true

class CreateGameScoringReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :game_scoring_reviews do |t|
      t.references :season, null: false, foreign_key: true
      t.references :schedule_refresh_run, null: false, foreign_key: true
      t.references :source_observation, null: false, foreign_key: { to_table: :game_observations }, index: { unique: true }
      t.references :reviewed_by, null: false, foreign_key: { to_table: :users }
      t.string :source_fingerprint, null: false, index: { unique: true }
      t.string :reason, null: false, default: 'Approved by admin'
      t.jsonb :choices, null: false, default: {}
      t.jsonb :approved_payload, null: false, default: {}
      t.jsonb :participants, null: false, default: {}
      t.timestamps
    end
    add_reference :game_observations, :scoring_review, foreign_key: { to_table: :game_scoring_reviews }
    add_index :game_observations, :scoring_review_id, unique: true, where: 'accepted = true',
              name: 'index_one_accepted_observation_per_scoring_review'
  end
end
