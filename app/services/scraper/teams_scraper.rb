require 'csv'

module Scraper
  class TeamsScraper < Scraper
    def initialize
      @schools_url = "#{BASE_URL}/cbb/schools"
      @max_year = 2023
    end

    def to_csv(file_path)
      teams = scrape_teams
      write_to_csv(teams, file_path)
    end

    private

    def digest_row(row)
      {
        school_name: row.css("td[data-stat='school_name']")&.text,
        url: row.css("td[data-stat='school_name'] a")&.attribute("href")&.value,
        location: row.css("td[data-stat='location']")&.text,
        latest_year: row.css("td[data-stat='year_max']")&.text.to_i,
      } 
    end

    def scrape_teams
      response = HTTParty.get(@schools_url)
      document = Nokogiri::HTML(response.body)

      teams = document.css("table#NCAAM_schools tbody tr").
        map { |row| digest_row(row) }.
        reject { |row| row[:school_name].empty?  }.
        reject { |row| row[:latest_year] != @max_year }

      teams
    end

    def parse_school_name(school_name)
      name_array = school_name.split

      return name_array[0], name_array[1] if name_array.length == 2
    end

    def write_to_csv(teams, file_path)
      file_path ||= "scraped_teams.csv"
      CSV.open(file_path, 'w',
        write_headers: true,
        headers: ["full_name", "school", "nickname", "url", "location"] ) do |writer|
        teams.each do |team|
          school, nickname = parse_school_name(team[:school_name])
          writer << [team[:school_name], school, nickname, team[:url], team[:location]]
        end
      end
    end
  end
end
