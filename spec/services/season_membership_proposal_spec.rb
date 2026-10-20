# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonMembershipProposal do
  def query_count(&)
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      count += 1 if %w[SELECT INSERT UPDATE DELETE].any? { |verb| sql.match?(/\A\s*#{verb}\b/i) } && !payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    count
  end

  it 'selects membership years from a preloaded collection without queries' do
    start = create(:season, year: 2025)
    finish = create(:season, year: 2027)
    conference = create(:conference)
    team = create(:team)
    create(:team_conference, team:, conference:, start_season: start, end_season: finish)
    loaded_team = Team.includes(team_conferences: %i[conference start_season end_season]).find(team.id)

    expect(query_count { described_class.memberships_at(loaded_team, 2026).map(&:conference_id) }).to eq(0)
  end

  it 'keeps proposal query count bounded as teams and historical ranges grow' do
    seasons = (2000..2010).map { |year| create(:season, year:) }
    conference = create(:conference)
    first = create(:team, school: 'Single Fixture')
    add_ranges(first, conference, seasons)
    one_team_queries = query_count { described_class.build_rows([], { target: 2009, source: 2009 }) }

    3.times do |index|
      team = create(:team, school: "Expanded Fixture #{index}")
      add_ranges(team, conference, seasons)
    end
    expanded_queries = query_count { described_class.build_rows([], { target: 2009, source: 2009 }) }

    expect(expanded_queries).to eq(one_team_queries)
  end

  def add_ranges(team, conference, seasons)
    [0, 2, 4, 6, 8].each_with_index do |offset, index|
      create(:team_conference, team:, conference:, start_season: seasons[offset], end_season: index == 4 ? nil : seasons[offset + 1])
    end
  end
end
