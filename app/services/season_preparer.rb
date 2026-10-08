# frozen_string_literal: true

class SeasonPreparer
  Result = Data.define(:season, :team_seasons_created)

  attr_reader :year, :start_date, :end_date

  def initialize(year:, start_date: nil, end_date: nil)
    @year = self.class.parse_year(year)
    @start_date = start_date
    @end_date = end_date
  end

  def call
    Season.with_ratings_lock do
      Season.transaction do
        season = prepare_season
        season.save! if season.changed?
        Result.new(season:, team_seasons_created: ensure_team_seasons(season))
      end
    end
  end

  def self.parse_year(value)
    text = value.to_s
    raise ArgumentError, 'YEAR must be an integer from 1 to 9999' unless /\A[0-9]{1,4}\z/.match?(text) && text.to_i.positive?

    Integer(text, 10)
  end

  private

  def prepare_season
    Season.find_or_initialize_by(year:).tap do |season|
      season.assign_attributes(prepared_attributes(season))
    end
  end

  def prepared_attributes(season)
    first = start_date || season.start_date || resolved_start_date
    last = end_date || season.end_date || resolved_end_date
    raise ArgumentError, 'end_date must be after start_date' if last <= first

    {
      name: season.name || season_name,
      start_date: first,
      end_date: last,
      average_efficiency: season.average_efficiency || season_default(:average_efficiency),
      average_pace: season.average_pace || season_default(:average_pace)
    }
  end

  def ensure_team_seasons(season)
    existing_team_ids = TeamSeason.where(season_id: season.id).pluck(:team_id).to_set
    created = 0

    Team.find_each do |team|
      next if existing_team_ids.include?(team.id)

      TeamSeason.create!(team:, season:)
      created += 1
    end

    created
  end

  def season_name
    "#{year - 1}-#{year.to_s[-2, 2]}"
  end

  def resolved_start_date
    @resolved_start_date ||= start_date || default_season_dates.first
  end

  def resolved_end_date
    @resolved_end_date ||= end_date || default_season_dates.last
  end

  def default_season_dates
    @default_season_dates ||= begin
      previous_season = Season.find_by(year: year - 1)
      if previous_season
        [previous_season.start_date.next_year, previous_season.end_date.next_year]
      else
        [Date.new(year - 1, 11, 1), Date.new(year, 4, 10)]
      end
    end
  end

  def season_default(key)
    season_defaults.fetch(key)
  end

  def season_defaults
    @season_defaults ||= Rails.application.config_for(:defaults)[:season_defaults] || {}
  end
end
