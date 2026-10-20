# frozen_string_literal: true

class PreservePredictionProbabilityPrecision < ActiveRecord::Migration[8.1]
  def up
    # PostgreSQL float limits are binary precision bits, not byte counts.
    change_column :predictions, :home_win_probability, :float, limit: 53
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Keep double precision storage on code rollback; narrowing loses issued probabilities'
  end
end
