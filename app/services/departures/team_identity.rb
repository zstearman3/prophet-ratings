# frozen_string_literal: true

module Departures
  # Exact canonical names plus aliases belonging to the selected source host.
  class TeamIdentity
    def initialize(teams: Team.includes(:team_aliases).order(:id).to_a)
      resolver = self.class
      @canonical = resolver.canonical(teams)
      @aliases = resolver.alias_map(teams)
      @ids = teams.map(&:id)
    end

    def self.canonical(teams)
      teams.group_by { |team| team.school.to_s.strip }.transform_values { |group| group.map(&:id) }
    end

    def self.alias_map(teams)
      teams.flat_map { |team| aliases(team) }.group_by { |entry| entry.fetch(:key) }
    end

    def self.aliases(team)
      team.team_aliases.map { |entry| { key: [entry.source, entry.value.strip], id: team.id } }
    end

    def candidates(label, source:)
      name = label.to_s.strip
      (@canonical.fetch(name, []) + @aliases.fetch([source, name], []).pluck(:id)).uniq.sort
    end

    attr_reader :ids
  end
end
