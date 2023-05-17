require 'pry'
module Scraper
  class TeamScraper < Scraper
    def scrape
      response = HTTParty.get(schools_url)
      document = Nokogiri::HTML(response.body)

      set_max_year(document)

      teams = document.css("table#NCAAM_schools tbody tr").
        map { |row| digest_row(row) }.
        reject { |row| row[:school_name].empty?  }.
        reject { |row| row[:latest_year] != @max_year }

      teams.map { |team| scrape_team_details(team) }
      teams.each { |team| create_from_row(team) }
    end

    private

    def schools_url
      "#{BASE_URL}/cbb/schools"
    end

    def set_max_year(document)
      @max_year = document.css("table#NCAAM_schools tbody tr td[data-stat='year_max']").
        map { |row| row.text.to_i }.max
    end

    def digest_row(row)
      {
        school_name: row.css("td[data-stat='school_name']")&.text,
        url: row.css("td[data-stat='school_name'] a")&.attribute("href")&.value,
        location: row.css("td[data-stat='location']")&.text,
        latest_year: row.css("td[data-stat='year_max']")&.text.to_i,
      } 
    end

    # method to add any additional details found on other pages in the future
    def scrape_team_details(team)
      team
    end

    def parse_school_name(school_name)
      name_array = school_name.split

      return name_array[0], name_array[1] if name_array.length == 2

      puts school_name
    end

    def create_from_row(row)
      school, nickname = parse_school_name(row[:school_name])
      Team.find_or_create_by(school: school, nickname: nickname)
    end
  end
end
