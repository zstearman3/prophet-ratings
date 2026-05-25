# frozen_string_literal: true

class AddGameLookupIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :games, :url, algorithm: :concurrently unless index_exists?(:games, :url)

    unless index_exists?(:games, %i[home_team_name away_team_name start_time], name: 'index_games_on_teams_and_start_time')
      add_index :games,
                %i[home_team_name away_team_name start_time],
                name: 'index_games_on_teams_and_start_time',
                algorithm: :concurrently
    end

    return if index_exists?(:predictions, %i[game_id created_at], name: 'index_predictions_on_game_id_and_created_at')

    add_index :predictions,
              %i[game_id created_at],
              name: 'index_predictions_on_game_id_and_created_at',
              algorithm: :concurrently
  end
end
