# frozen_string_literal: true

class AddMembershipProposalToSeasons < ActiveRecord::Migration[8.1]
  def change
    add_column :seasons, :membership_proposal, :jsonb, null: false, default: {}
  end
end
