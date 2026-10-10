# frozen_string_literal: true

class AddParticipationReviewToSeasons < ActiveRecord::Migration[8.1]
  def change
    add_column :seasons, :participation_review, :jsonb, null: false, default: {}
  end
end
