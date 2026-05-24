# frozen_string_literal: true

namespace :games do
  desc 'Report duplicate games by default; set APPLY=true to repair/delete duplicates.'
  task dedupe: :environment do
    scope = if ENV['SEASON_ID'].present?
              Season.find(ENV.fetch('SEASON_ID')).games
            elsif ENV['YEAR'].present?
              Season.find_by!(year: ENV.fetch('YEAR')).games
            else
              Game.all
            end

    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', false))
    result = Maintenance::DuplicateGamesRepair.new(scope:, apply:).call

    puts "Deleted games: #{result.deleted_game_ids.join(', ')}" if result.deleted_game_ids.any?
    puts "Reassigned/deleted associations: #{result.reassigned_counts.inspect}" if result.reassigned_counts.any?
  end
end
