# frozen_string_literal: true

class UpdateTeamConferenceNaturalKey < ActiveRecord::Migration[8.0]
  OLD_INDEX_NAME = 'index_team_conferences_on_team_and_season_range'
  NEW_INDEX_NAME = 'index_team_conferences_on_team_and_start_season'
  OPEN_ENDED_YEAR = 2_147_483_647

  def up
    raise_if_duplicate_natural_keys
    raise_if_overlapping_ranges

    remove_index :team_conferences, name: OLD_INDEX_NAME if index_name_exists?(:team_conferences, OLD_INDEX_NAME)
    add_index :team_conferences, %i[team_id start_season_id], unique: true, name: NEW_INDEX_NAME
  end

  def down
    remove_index :team_conferences, name: NEW_INDEX_NAME if index_name_exists?(:team_conferences, NEW_INDEX_NAME)
    add_index :team_conferences,
              %i[team_id start_season_id end_season_id],
              unique: true,
              name: OLD_INDEX_NAME
  end

  private

  def raise_if_duplicate_natural_keys
    duplicates = execute(<<~SQL.squish).to_a
      SELECT team_id,
             start_season_id,
             ARRAY_AGG(id ORDER BY id) AS ids,
             COUNT(*) AS count
      FROM team_conferences
      GROUP BY team_id, start_season_id
      HAVING COUNT(*) > 1
      ORDER BY team_id, start_season_id
    SQL

    return if duplicates.empty?

    conflicts = duplicates.map do |row|
      "team_id=#{row['team_id']} start_season_id=#{row['start_season_id']} ids=#{row['ids']}"
    end.join('; ')

    raise ActiveRecord::MigrationError, "Duplicate team conference natural keys exist: #{conflicts}"
  end

  def raise_if_overlapping_ranges
    overlaps = execute(<<~SQL.squish).to_a
      SELECT earlier.id AS earlier_id,
             later.id AS later_id,
             earlier.team_id
      FROM team_conferences earlier
      INNER JOIN team_conferences later
        ON later.team_id = earlier.team_id
       AND later.id > earlier.id
      INNER JOIN seasons earlier_start
        ON earlier_start.id = earlier.start_season_id
      LEFT JOIN seasons earlier_end
        ON earlier_end.id = earlier.end_season_id
      INNER JOIN seasons later_start
        ON later_start.id = later.start_season_id
      LEFT JOIN seasons later_end
        ON later_end.id = later.end_season_id
      WHERE earlier_start.year <= COALESCE(later_end.year, #{OPEN_ENDED_YEAR})
        AND later_start.year <= COALESCE(earlier_end.year, #{OPEN_ENDED_YEAR})
      ORDER BY earlier.team_id, earlier.id, later.id
    SQL

    return if overlaps.empty?

    conflicts = overlaps.map do |row|
      "team_id=#{row['team_id']} ids=#{row['earlier_id']},#{row['later_id']}"
    end.join('; ')

    raise ActiveRecord::MigrationError, "Overlapping team conference ranges exist: #{conflicts}"
  end
end
