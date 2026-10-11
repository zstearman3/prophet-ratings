# frozen_string_literal: true

require 'uri'

module Recruiting
  # The observed 247 ranking markup, including its load-more fragments.
  class HtmlPage
    attr_reader :document, :url, :year

    def initialize(html, url, year)
      @url = url
      @year = year
      HtmlPage.validate_url(url, year)
      @document = HtmlPage.parse_document(html)
      validate_identity
    end

    def self.parse_document(html)
      text = html.dup.force_encoding(Encoding::UTF_8)
      raise ArgumentError, 'Source HTML is not UTF-8' unless text.valid_encoding?

      Nokogiri::HTML(text)
    end

    def self.source_url(year)
      "https://247sports.com/Season/#{year}-Basketball/CompositeTeamRankings/"
    end

    def self.parse_url(url)
      URI.parse(url)
    rescue URI::Error => error
      raise ArgumentError, "Invalid source URL: #{error.message}"
    end

    def self.validate_url(url, year)
      uri = parse_url(url)
      expected = "/season/#{year}-basketball/compositeteamrankings/"
      unless uri.scheme == 'https' && uri.host == '247sports.com' && uri.path.downcase == expected && valid_query?(uri.query)
        raise ArgumentError, 'Unsupported source URL/category/year/scope'
      end

      url
    end

    def self.valid_query?(query)
      URI.decode_www_form(query.to_s).all? do |key, value|
        (key == 'Page' && value.match?(/\A[1-9]\d*\z/)) ||
          (key == 'ViewPath' && value == '~/Views/SkyNet/InstitutionRanking/_SimpleSetForSeason.ascx')
      end
    end

    def rows
      document.css('.rankings-page__list-item').map { |node| self.class.row(node, year) }
    end

    def next_url
      links = document.css('a[data-js="showmore"]')
      raise ArgumentError, 'Conflicting pagination links' if links.many?

      checked_link(links.first&.[]('href'))
    end

    def source_updated_text
      node = document.at_css('.last-updated')
      self.class.direct_text(node) if node
    end

    def self.row(node, year)
      link = node.at_css('.team .rankings-page__name-link')
      href = link&.[]('href')
      provider_id = team_identity(href, year)

      label = link&.text
      {
        'team_label' => label&.strip, 'raw_team_label' => label, 'provider_team_id' => provider_id, 'team_url' => href,
        'rank' => field(node, '.rank-column .primary'), 'class_points' => field(node, '.points .number'),
        'average_rating' => field(node, '.avg'), 'commit_count' => commits(node)
      }
    end

    def self.team_identity(href, year)
      return if href.blank? || href == "https://247sports.com/season/#{year}-basketball/commits/"

      match = href.to_s.match(%r{\Ahttps://247sports.com/college/([^/]+)/season/#{year}-basketball/commits/\z}i)
      raise ArgumentError, 'Malformed or wrong-year source team URL' unless match

      match[1]
    end

    def self.field(node, selector)
      node.at_css(selector)&.text&.strip.presence
    end

    def self.commits(node)
      text = field(node, '.total')
      return unless text

      match = text.match(/\A(\d+) Commits?\z/)
      raise ArgumentError, 'Malformed commit count' unless match

      match[1]
    end

    def self.direct_text(node)
      node.children.select(&:text?).map(&:text).join.strip
    end

    private

    def checked_link(href)
      return unless href

      link = URI.join(url, href).to_s
      self.class.validate_url(link, year)
    rescue URI::Error => error
      raise ArgumentError, "Invalid pagination URL: #{error.message}"
    end

    def validate_identity
      heading = document.at_css('h1.rankings-page__heading')
      heading ? validate_heading(heading) : validate_fragment
      return if document.at_css('.rankings-page__list') || document.at_css('.rankings-page__list-item')

      raise ArgumentError, 'Unrecognized source: missing rankings container'
    end

    def validate_heading(heading)
      validator = self.class
      text = validator.direct_text(heading)
      raise ArgumentError, 'Wrong source heading/category/year' unless text == "#{year} Recruit Basketball Composite Team Rankings"

      validate_scope
    end

    def validate_scope
      canonical = document.at_css('link[rel="canonical"]')&.[]('href')
      self.class.validate_url(canonical.to_s, year)
      selected = document.at_css('.rankings-page__conference-list .current a')&.text&.strip
      raise ArgumentError, 'Source must select ALL conferences' unless selected == 'ALL'
    end

    def validate_fragment
      return if URI.decode_www_form(URI.parse(url).query.to_s).to_h.key?('Page')

      raise ArgumentError, 'Unrecognized source: missing ranking heading'
    end
  end
end
