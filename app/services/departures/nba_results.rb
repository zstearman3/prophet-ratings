# frozen_string_literal: true

module Departures
  # NBA news result pages use numbered paragraphs under two round headings.
  class NbaResults
    def initialize(source:, html:, draft_year:)
      @source = source
      @document = Nokogiri::HTML(html)
      @draft_year = draft_year
    end

    ROUND_LABELS = { 'First Round' => 1, 'Second Round' => 2 }.freeze

    def call
      validate_title
      rows = parsed_rows
      validate_rows(rows)
      rows.sort_by { |row| row.fetch('overall_pick') }
    end

    def self.validate_rows(rows)
      Contract.check!(rows.any? && rows.pluck('round').uniq.sort == [1, 2], 'Missing draft round results')
      Contract.unique!(rows.pluck('overall_pick'), 'selection keys')
      Contract.unique!(rows.pluck('player_source_url'), 'draft player identities')
    end

    def self.unique_identity(identities)
      Contract.check!(identities.one?, 'Missing or ambiguous draft player URL')
      identities.first
    end

    private

    attr_reader :source, :document, :draft_year

    def validate_title
      title = document.at_css('h1')&.text.to_s
      Contract.check!(title.match?(/\A#{draft_year} NBA Draft Results\b/), 'Unsupported draft results title/year')
    end

    def validate_full_results(rows)
      last_pick = document.at_css('h1')&.text.to_s[/Picks 1[-–](\d+)\b/, 1]
      Contract.check!(last_pick.present? && rows.pluck('overall_pick').sort == (1..Integer(last_pick, 10)).to_a,
                      'Partial draft results: selections disagree with published pick range')
    end

    def parsed_rows
      round = nil
      document.css('h2, p').filter_map do |node|
        kind = node.name
        round = ROUND_LABELS.fetch(node.text.strip, round) if kind == 'h2'
        selection(node, round) if kind == 'p' && round
      end
    end

    def validate_rows(rows)
      self.class.validate_rows(rows)
      validate_full_results(rows)
    end

    def selection(node, round)
      text = node.text.strip
      match = text.match(/\A(\d+)\.\s+.+?\bdraft\s+(.+)\z/)
      return unless match

      links = player_links(node)
      selection_attributes(match, round).merge('player_name_source' => links.map(&:text).join.strip,
                                               'player_source_url' => player_identity(links),
                                               'selection_text_source' => text)
    end

    def player_links(node)
      node.css('a[href]').select { |link| link['href'].include?("/draft/#{draft_year}/prospects/") }
    end

    def player_identity(links)
      identities = links.map { |link| URI.join(source.fetch('url'), link['href']).to_s }.uniq
      self.class.unique_identity(identities)
    end

    def selection_attributes(match, round)
      pick = Integer(match[1], 10)
      Contract.check!((1..60).cover?(pick) && round == (pick <= 30 ? 1 : 2), 'Invalid pick/round')
      { 'selection_key' => "#{draft_year}/#{pick}", 'overall_pick' => pick, 'round' => round,
        'affiliation_source' => match[2][/\(([^)]*)\)/, 1], 'source_id' => source.fetch('id'),
        'draft_source_url' => source.fetch('url') }
    end
  end
end
