# frozen_string_literal: true

require_relative 'notion'

module ReleaseTool
  # Git determines inclusion; Notion enriches only explicitly linked PRs.
  class Notes
    def initialize(repo, notion: Notion.new)
      @repo = repo
      @notion = notion
    end

    def render(plan)
      formatter = self.class
      groups = plan.fetch(:commits).map { |commit| entry(commit) }.group_by(&:first)
      notes = ["# Release #{plan.fetch(:version)}", formatter.provenance(plan),
               "[Compare changes](https://github.com/#{@repo}/compare/#{plan.fetch(:base)}...#{plan.fetch(:target)})",
               *formatter.sections(groups)].join("\n\n")
      "#{notes}\n"
    end

    def self.provenance(plan)
      "Candidate: `#{plan.fetch(:target)}` (development). Production baseline: `#{plan.fetch(:base)}`."
    end

    def self.sections(groups)
      groups.map { |name, entries| "## #{escape(name)}\n\n#{entries.map(&:last).uniq.join("\n")}" }
    end

    def self.escape(text)
      text.to_s.gsub(/\s+/, ' ').strip.gsub(/[\\\[\]`*_<>]/) { |character| "\\#{character}" }
    end

    def self.number(subject)
      subject[/\(#(\d+)\)\z/, 1] || subject[/\AMerge pull request #(\d+)\b/, 1]
    end

    def self.matching_pull_request(pull_request, commit)
      [pull_request].find { |item| item['state'] == 'MERGED' && item.dig('mergeCommit', 'oid') == commit.first }
    end

    def self.direct(commit, repo)
      sha, subject = commit
      ['Other commits', "- [#{sha[0, 7]}](https://github.com/#{repo}/commit/#{sha}) #{escape(subject)}"]
    end

    def self.dependency?(pull_request)
      %w[dependabot dependabot[bot] app/dependabot].include?(pull_request.dig('author', 'login'))
    end

    def self.format_entry(pull_request, tickets)
      title = "#{escape(pull_request.fetch('title'))} (##{pull_request.fetch('number')})"
      [group(pull_request, tickets), "- [#{title}](#{pull_request.fetch('url')})#{ticket_links(tickets)}"]
    end

    def self.group(pull_request, tickets)
      return 'Dependabot updates' if dependency?(pull_request)
      return 'No Notion ticket' if tickets.empty?

      tickets.map { |ticket| ticket.fetch(:status) }.uniq.join(' / ')
    end

    def self.ticket_links(tickets)
      links = tickets.map { |ticket| ticket_link(ticket) }
      links.empty? ? '' : " — #{links.join(', ')}"
    end

    def self.ticket_link(ticket)
      title = ticket.fetch(:title)
      "[#{escape(title.empty? ? 'Notion work item' : title)}](#{ticket.fetch(:url)})"
    end

    private

    def entry(commit)
      pull_request = pull_request(commit)
      pull_request ? linked_entry(pull_request) : self.class.direct(commit, @repo)
    end

    def linked_entry(pull_request)
      self.class.format_entry(pull_request, tickets_for(pull_request))
    end

    def tickets_for(pull_request)
      return [] if self.class.dependency?(pull_request)

      @notion.tickets(pull_request.fetch('body'))
    end

    def pull_request(commit)
      formatter = self.class
      number = formatter.number(commit.last)
      return unless number

      result = ReleaseTool.json('gh', 'pr', 'view', number, '--repo', @repo, '--json', 'number,title,body,url,author,state,mergeCommit')
      formatter.matching_pull_request(result, commit)
    end
  end
end
