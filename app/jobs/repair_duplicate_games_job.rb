# frozen_string_literal: true

class RepairDuplicateGamesJob < ApplicationJob
  queue_as :default

  def perform(season_id: nil, year: nil, apply: false)
    apply = ActiveModel::Type::Boolean.new.cast(apply)
    scope = game_scope(season_id:, year:)
    output = StringIO.new
    result = Maintenance::DuplicateGamesRepair.new(scope:, apply:, output:).call

    Rails.logger.info do
      "Duplicate game repair #{result.applied ? 'applied' : 'dry run'}: " \
        "groups=#{result.groups.size}, deleted=#{result.deleted_game_ids.size}, " \
        "reassigned=#{result.reassigned_counts.inspect}"
    end

    Rails.logger.debug { output.string } if output.string.present?
  end

  private

  def game_scope(season_id:, year:)
    if season_id.present?
      Season.find(season_id).games
    elsif year.present?
      Season.find_by!(year:).games
    else
      Game.all
    end
  end
end
