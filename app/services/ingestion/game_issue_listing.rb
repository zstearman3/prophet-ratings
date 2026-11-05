# frozen_string_literal: true

module Ingestion
  # One bounded admin listing; source payloads are loaded only for the visible page.
  class GameIssueListing
    def initialize(filters)
      @filters = filters
    end

    def call
      page_number = [@filters[:page].to_i, 1].max
      issues = filtered.includes(:season, :game, :latest_observation).order(id: :desc).limit(50).offset((page_number - 1) * 50)
      { issues:, page_number:, seasons: Season.order(year: :desc) }
    end

    private

    def filtered
      scope = GameIngestionIssue.where(@filters.slice(:season_id).to_h.compact_blank)
      category = @filters[:category]
      scope = scope.where(category:) if GameIngestionIssue::CATEGORIES.include?(category)
      filter_date(filter_state(scope))
    end

    def filter_state(scope)
      return scope if @filters[:state] == 'all'

      scope.where(state: selected_state)
    end

    def selected_state
      @filters[:state] == 'resolved' ? 'resolved' : 'open'
    end

    def filter_date(scope)
      date = @filters[:date]
      return scope if date.blank?

      observations = ::GameObservation.where("normalized_payload ->> 'schedule_date' = ?", Date.iso8601(date).iso8601)
      scope.where(latest_observation_id: observations.select(:id))
    end
  end
end
