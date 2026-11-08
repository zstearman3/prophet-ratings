# frozen_string_literal: true

class CreateBetRecommendationIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :bet_recommendation_issues do |t|
      t.references :game, null: false, foreign_key: { on_delete: :cascade }
      t.references :prediction, null: false, foreign_key: { on_delete: :cascade }
      t.references :ratings_config_version, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :issued_at, null: false
      t.datetime :captured_start_time, null: false
      t.datetime :odds_fetched_at
      t.jsonb :evidence, null: false
      t.index [:game_id, :prediction_id, :issued_at], name: 'index_bet_issues_on_game_prediction_issuance'
    end
  end
end
