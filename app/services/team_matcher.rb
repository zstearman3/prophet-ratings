# frozen_string_literal: true

class TeamMatcher
  def initialize
    @teams = Team.includes(:team_aliases).to_a

    # Build normalized alias map for fast lookup
    @alias_map = {}
    @teams.each do |team|
      team.team_aliases.each do |team_alias|
        normalized = normalize(team_alias.value)
        @alias_map[normalized] = team
      end
    end

    # Hash of Team => array of names for fuzzy matching
    @team_to_names = @teams.each_with_object({}) do |team, hash|
      names = []
      names << team.school
      names.concat(team.team_aliases.map(&:value))
      names.compact!
      names.uniq!

      hash[team] = names
    end

    @fuzzy_matcher = FuzzyMatch.new(
      @team_to_names,
      read: ->(team) { @team_to_names[team] }
    )
  end

  def match(input_name)
    normalized_input = normalize(input_name)

    # 1. Exact match on school
    team = @teams.find { |t| t.school.casecmp?(input_name) }
    return team if team

    # 2. Exact match on normalized alias
    return @alias_map[normalized_input] if @alias_map.key?(normalized_input)

    # 3. Fuzzy match across all known names
    @fuzzy_matcher.find(input_name)
  end

  private

  def normalize(str)
    str.downcase.gsub(/[^a-z0-9]/, '')
  end
end
