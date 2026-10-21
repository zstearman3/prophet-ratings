# frozen_string_literal: true

module Admin
  # Escaped structured evidence, without a raw JSON editor or capture body endpoint.
  module CbbdReviewRunsHelper
    def cbbd_evidence(value)
      case value
      when Hash then cbbd_hash_evidence(value)
      when Array then safe_join(value.map { |item| tag.div(cbbd_evidence(item), class: 'border-l pl-2 my-1') })
      when NilClass then 'Unknown'
      else ERB::Util.html_escape(value.to_s)
      end
    end

    def cbbd_hash_evidence(value)
      safe_join(value.except('sha256', 'fingerprint', 'body_file').map do |key, item|
        tag.div(tag.strong("#{key.humanize}: ") + cbbd_evidence(item), class: 'ml-3 my-1')
      end)
    end

    def cbbd_target_options(row)
      row.fetch('candidate_ids').map { |id| ["#{cbbd_target_label(id)} (#{id})", id] }
    end

    def cbbd_target_label(id)
      return Team.find_by(id:)&.school || 'Stored team' if page.entity == 'team'

      names = Game.find_by(id:)&.attributes&.values_at('home_team_name', 'away_team_name')
      names&.join(' / ') || 'Stored game'
    end

    def cbbd_review_token(comparison)
      hidden_field_tag('review[comparison_id]', comparison.id) +
        hidden_field_tag('review[draft_revision]', comparison.draft_revision)
    end
  end
end
