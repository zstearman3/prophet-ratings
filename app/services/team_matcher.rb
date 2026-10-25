# frozen_string_literal: true

class TeamMatcher
  def initialize
    @teams = Team.includes(:team_aliases).to_a

    @alias_map = build_alias_map
    @team_to_names = @teams.index_with { |team| [team.school, *team.team_aliases.map(&:value)].compact.uniq }

    @fuzzy_matcher = FuzzyMatch.new(
      @team_to_names,
      read: method(:names_for).to_proc
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

  def build_alias_map
    @teams.each_with_object({}) do |team, aliases|
      add_aliases(team, aliases)
    end
  end

  def names_for(team)
    @team_to_names[team]
  end

  def add_aliases(team, aliases)
    team.team_aliases.each { |team_alias| aliases[normalize(team_alias.value)] = team }
  end

  def normalize(str)
    str.downcase.gsub(/[^a-z0-9]/, '')
  end
end
