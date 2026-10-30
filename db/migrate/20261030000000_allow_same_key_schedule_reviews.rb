# frozen_string_literal: true

class AllowSameKeyScheduleReviews < ActiveRecord::Migration[8.1]
  def change
    remove_index :game_schedule_reviews, :ignored_external_id, unique: true
    add_index :game_schedule_reviews, :ignored_external_id
    add_index :game_schedule_reviews, :ignored_external_id, unique: true,
                                                         where: 'selected_external_id <> ignored_external_id',
                                                         name: 'index_one_retired_schedule_game_key'
  end
end
