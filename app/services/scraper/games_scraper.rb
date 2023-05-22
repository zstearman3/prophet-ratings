module Scraper
  class GamesScraper < Scraper
    def initialize(date=Date.today)
      @date = date
      @games_url = schedule_url(@date)
    end

    def to_json
      scrape_day(@date)
    end

    private

    def schedule_url(date)
      "#{BASE_URL}/cbb/boxscores/index.cgi?month=#{date.strftime('%-m')}"\
      "&day=#{date.strftime('%-d')}&year=#{date.strftime('%Y')}"
    end

    def game_url(url)
      BASE_URL + url
    end

    def game_urls(document)
      document.css("div.game_summaries div.gender-m")&.
               css("td.gamelink a")&.map { |link| link&.attribute("href")&.value }
    end

    def parse_team_stats(row)
      {
        minutes: row.css("td[data-stat='mp']")&.text,
        field_goals_made: row.css("td[data-stat='fg']")&.text,
        field_goals_attempted: row.css("td[data-stat='fga']")&.text,
        two_pt_made: row.css("td[data-stat='fg2']")&.text,
        two_pt_attempted: row.css("td[data-stat='fg2a']")&.text,
        three_pt_made: row.css("td[data-stat='fg3']")&.text,
        three_pt_attempted: row.css("td[data-stat='fg3a']")&.text,
        free_throws_made: row.css("td[data-stat='ft']")&.text,
        free_throws_attempted: row.css("td[data-stat='fta']")&.text,
        offensive_rebounds: row.css("td[data-stat='orb']")&.text,
        defensive_rebounds: row.css("td[data-stat='drb']")&.text,
        rebounds: row.css("td[data-stat='trb']")&.text,
        assists: row.css("td[data-stat='ast']")&.text,
        steals: row.css("td[data-stat='stl']")&.text,
        blocks: row.css("td[data-stat='blk']")&.text,
        turnovers: row.css("td[data-stat='tov']")&.text,
        fouls: row.css("td[data-stat='pf']")&.text,
        points: row.css("td[data-stat='pts']")&.text,
      }
    end

    def scrape_game(url)
      # To comply with sports reference TOS
      sleep(3.5)

      response = HTTParty.get(game_url(url))
      document = Nokogiri::HTML(response.body)

      team_boxes = document.css("div.scorebox")&.xpath('./div')
      home_team = team_boxes[1]&.css("strong a")&.text
      away_team = team_boxes[0]&.css("strong a")&.text
      home_team_score = team_boxes[1]&.css("div.score")&.text
      away_team_score = team_boxes[0]&.css("div.score")&.text
      date = document.css("div.scorebox_meta div")[0]&.text
      location = document.css("div.scorebox_meta div")[1]&.text
      away_team_line = document.css("table.stats_table tfoot tr")[0]
      home_team_line = document.css("table.stats_table tfoot tr")[2]

      { 
        home_team: home_team, 
        away_team: away_team,
        home_team_score: home_team_score,
        away_team_score: away_team_score,
        date: date,
        location: location,
        away_team_stats: parse_team_stats(away_team_line),
        home_team_stats: parse_team_stats(home_team_line),
        url: url,
      }
    end

    def scrape_day(date=Date.today)
      response = HTTParty.get(schedule_url(date))
      document = Nokogiri::HTML(response.body)

      game_urls = game_urls(document)

      game_urls.map { |url| scrape_game(url) }
    end
  end
end
