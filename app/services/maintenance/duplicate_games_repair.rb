# frozen_string_literal: true

module Maintenance
  class DuplicateGamesRepair
    Result = Struct.new(:applied, :groups, :deleted_game_ids, :reassigned_counts, keyword_init: true)
    DuplicateGroup = Struct.new(:games, :survivor, :duplicates, :reasons, keyword_init: true)

    def initialize(scope: Game.all, apply: false, output: $stdout)
      @scope = scope
      @apply = apply
      @output = output
      @deleted_game_ids = []
      @reassigned_counts = Hash.new(0)
    end

    def call
      groups = duplicate_groups
      report(groups)
      apply_repairs(groups) if apply

      Result.new(
        applied: apply,
        groups:,
        deleted_game_ids: deleted_game_ids,
        reassigned_counts: reassigned_counts
      )
    end

    private

    attr_reader :scope, :apply, :output, :deleted_game_ids, :reassigned_counts

    def duplicate_groups
      game_rows = games
      key_map = duplicate_key_map(game_rows)
      grouped_components(game_rows, key_map).filter_map do |component_games|
        next if component_games.size < 2

        survivor = survivor_for(component_games)
        DuplicateGroup.new(
          games: component_games,
          survivor:,
          duplicates: component_games - [survivor],
          reasons: reasons_for(component_games, key_map)
        )
      end
    end

    def games
      @games ||= scope.includes(
        :home_team_game,
        :away_team_game,
        :predictions,
        :game_odd,
        :bookmaker_odds,
        :bet_recommendations
      ).to_a
    end

    def duplicate_key_map(game_rows)
      game_rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |game, keys|
        duplicate_keys_for(game).each { |key| keys[key] << game }
      end
    end

    def grouped_components(game_rows, key_map)
      reset_union_find
      key_map.each_value do |matching_games|
        next if matching_games.size < 2

        matching_games.combination(2) { |left, right| union(left.id, right.id) }
      end

      game_rows.group_by { |game| find(game.id) }.values
    end

    def reset_union_find
      @parents = {}
    end

    def find(id)
      @parents[id] ||= id
      @parents[id] == id ? id : @parents[id] = find(@parents[id])
    end

    def union(left_id, right_id)
      @parents[find(right_id)] = find(left_id)
    end

    def duplicate_keys_for(game)
      keys = []
      keys << [:unique_url, normalized_url(game.url)] if unique_game_url?(game.url)

      duplicate_dates_for(game).each do |date|
        keys << [:ordered_team_date, normalized_team(game.home_team_name), normalized_team(game.away_team_name), date]
        next unless neutral_game?(game)

        keys << [:neutral_team_date, *normalized_team_pair(game), date]
      end

      keys
    end

    def duplicate_dates_for(game)
      dates = [game.schedule_date]
      dates << game.start_time.in_time_zone.to_date if legacy_date_only?(game)
      dates.uniq
    end

    def unique_game_url?(url)
      normalized_url(url).present? && !daily_schedule_url?(url)
    end

    def normalized_url(url)
      url.to_s.strip
    end

    def daily_schedule_url?(url)
      normalized_url(url).include?('/cbb/boxscores/index.cgi')
    end

    def normalized_team(team_name)
      team_name.to_s.squish.downcase
    end

    def normalized_team_pair(game)
      [normalized_team(game.home_team_name), normalized_team(game.away_team_name)].sort
    end

    def neutral_game?(game)
      game.neutral == true || game.venue_neutral?
    end

    def legacy_date_only?(game)
      time = game.start_time.in_time_zone
      time.hour.zero? && time.min.zero? && time.sec.zero?
    end

    def reasons_for(component_games, key_map)
      key_map.filter_map do |key, matching_games|
        key.first if (matching_games & component_games).size > 1
      end.uniq
    end

    def survivor_for(component_games)
      component_games.max_by { |game| [survivor_score(game), -game.id] }
    end

    def survivor_score(game)
      score = 0
      score += 1_000 if game.final?
      score += 200 if complete_team_games?(game)
      score += 100 if game.predictions.any?
      score += 80 if game.game_odd.present?
      score += 60 if game.bookmaker_odds.any?
      score += 50 if game.bet_recommendations.any?
      score += 40 if manual_venue?(game)
      score += 25 if venue_data_present?(game)
      score += 15 if unique_game_url?(game.url)
      score += 10 unless legacy_date_only?(game)
      score
    end

    def complete_team_games?(game)
      game.home_team_game.present? && game.away_team_game.present?
    end

    def manual_venue?(game)
      game.venue_confidence == 'manual' || game.venue_source == 'manual_override'
    end

    def venue_data_present?(game)
      !game.venue_unknown? || game.venue_source.present? || game.venue_name.present? || !game.neutral.nil?
    end

    def report(groups)
      output.puts(apply ? 'APPLYING duplicate game repair' : 'DRY RUN duplicate game repair')
      output.puts("Found #{groups.size} duplicate groups.")

      groups.each_with_index do |group, index|
        output.puts(group_summary(group, index + 1))
      end
    end

    def group_summary(group, index)
      game_ids = group.games.map(&:id).join(', ')
      duplicate_ids = group.duplicates.map(&:id).join(', ')
      "Group #{index}: reason=#{group.reasons.join(', ')} keep=#{group.survivor.id} " \
        "duplicates=#{duplicate_ids} all=#{game_ids}"
    end

    def apply_repairs(groups)
      groups.each do |group|
        ActiveRecord::Base.transaction do
          group.duplicates.each { |duplicate| merge_duplicate!(group.survivor, duplicate) }
        end
      end
    end

    def merge_duplicate!(survivor, duplicate)
      merge_game_attributes!(survivor, duplicate)
      reassign_team_games!(survivor, duplicate)
      reassign_predictions!(survivor, duplicate)
      reassign_game_odd!(survivor, duplicate)
      reassign_bookmaker_odds!(survivor, duplicate)
      reassign_bet_recommendations!(survivor, duplicate)
      reset_duplicate_associations(duplicate)
      duplicate.destroy!
      deleted_game_ids << duplicate.id
    end

    def reset_duplicate_associations(duplicate)
      %i[home_team_game away_team_game predictions game_odd bookmaker_odds bet_recommendations].each do |association_name|
        duplicate.association(association_name).reset
      end
    end

    def merge_game_attributes!(survivor, duplicate)
      attrs = merged_game_attributes(survivor, duplicate)
      return if attrs.empty?

      survivor.assign_attributes(attrs)
      survivor.save!(validate: false)
    end

    def merged_game_attributes(survivor, duplicate)
      {}.tap do |attrs|
        attrs[:url] = duplicate.url if !unique_game_url?(survivor.url) && unique_game_url?(duplicate.url)
        attrs[:start_time] = duplicate.start_time if legacy_date_only?(survivor) && !legacy_date_only?(duplicate)
        attrs.merge!(score_attributes_from(duplicate, survivor))
        attrs.merge!(venue_attributes_from(duplicate)) if !venue_data_present?(survivor) && venue_data_present?(duplicate)
      end
    end

    def score_attributes_from(duplicate, survivor)
      attrs = {}
      copy_if_blank(attrs, :home_team_score, from: duplicate, to: survivor)
      copy_if_blank(attrs, :away_team_score, from: duplicate, to: survivor)
      copy_if_blank(attrs, :minutes, from: duplicate, to: survivor)
      copy_if_blank(attrs, :possessions, from: duplicate, to: survivor)
      attrs[:status] = duplicate.status if survivor.scheduled? && duplicate.final?
      attrs
    end

    def copy_if_blank(attrs, attribute, from:, to:)
      value = from.public_send(attribute)
      attrs[attribute] = value if to.public_send(attribute).blank? && value.present?
    end

    def venue_attributes_from(game)
      {
        venue_type: game.venue_type,
        venue_source: game.venue_source,
        venue_confidence: game.venue_confidence,
        venue_name: game.venue_name,
        neutral: game.neutral
      }
    end

    def reassign_team_games!(survivor, duplicate)
      TeamGame.where(game: duplicate).find_each do |team_game|
        if TeamGame.exists?(game: survivor, home: team_game.home) || TeamGame.exists?(game: survivor, team_id: team_game.team_id)
          team_game.destroy!
          reassigned_counts[:team_games_deleted] += 1
        else
          team_game.update!(game: survivor)
          reset_team_game_associations(survivor)
          reassigned_counts[:team_games_reassigned] += 1
        end
      end
    end

    def reset_team_game_associations(game)
      game.association(:home_team_game).reset
      game.association(:away_team_game).reset
    end

    def reassign_predictions!(survivor, duplicate)
      duplicate.predictions.find_each do |prediction|
        if matching_prediction?(survivor, prediction)
          prediction.destroy!
          reassigned_counts[:predictions_deleted] += 1
        else
          prediction.update!(game: survivor)
          reassigned_counts[:predictions_reassigned] += 1
        end
      end
    end

    def matching_prediction?(survivor, prediction)
      Prediction.exists?(
        game: survivor,
        home_team_snapshot_id: prediction.home_team_snapshot_id,
        away_team_snapshot_id: prediction.away_team_snapshot_id
      )
    end

    def reassign_game_odd!(survivor, duplicate)
      game_odd = duplicate.game_odd
      return unless game_odd

      if survivor.game_odd
        game_odd.destroy!
        reassigned_counts[:game_odds_deleted] += 1
      else
        game_odd.update!(game: survivor)
        survivor.association(:game_odd).reset
        reassigned_counts[:game_odds_reassigned] += 1
      end
    end

    def reassign_bookmaker_odds!(survivor, duplicate)
      duplicate.bookmaker_odds.find_each do |bookmaker_odd|
        if matching_bookmaker_odd?(survivor, bookmaker_odd)
          bookmaker_odd.destroy!
          reassigned_counts[:bookmaker_odds_deleted] += 1
        else
          bookmaker_odd.update!(game: survivor)
          survivor.association(:bookmaker_odds).reset
          reassigned_counts[:bookmaker_odds_reassigned] += 1
        end
      end
    end

    def matching_bookmaker_odd?(survivor, bookmaker_odd)
      survivor.bookmaker_odds.find_by(
        bookmaker: bookmaker_odd.bookmaker,
        market: bookmaker_odd.market,
        team_name: bookmaker_odd.team_name
      )
    end

    def reassign_bet_recommendations!(survivor, duplicate)
      duplicate.bet_recommendations.find_each do |recommendation|
        if matching_bet_recommendation?(recommendation)
          recommendation.destroy!
          reassigned_counts[:bet_recommendations_deleted] += 1
        else
          recommendation.update!(game: survivor)
          reassigned_counts[:bet_recommendations_reassigned] += 1
        end
      end
    end

    def matching_bet_recommendation?(recommendation)
      BetRecommendation
        .where(
          prediction_id: recommendation.prediction_id,
          game_odd_id: recommendation.game_odd_id,
          bet_type: recommendation.bet_type
        )
        .where.not(id: recommendation.id)
        .exists?
    end
  end
end
