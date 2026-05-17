# frozen_string_literal: true

module ApplicationHelper
  DEFAULT_PAGE_TITLE = 'Prophet Ratings | College Basketball Predictions & Betting Insights'
  DEFAULT_PAGE_DESCRIPTION = [
    'College basketball ratings, matchup projections, and betting value indicators',
    'powered by Prophet Ratings.'
  ].join(' ')

  def icon_button(form, text:, icon_svg:, title:, **options)
    name  = options.delete(:name)
    value = options.delete(:value)
    css   = options.delete(:class)
    data  = options.delete(:data)

    icon = sanitize(
      icon_svg,
      tags: %w[svg path rect circle],
      attributes: %w[
        class fill stroke stroke-width viewBox d x y width height rx ry
        stroke-linecap stroke-linejoin cx cy r
      ]
    )

    form.button name:, value:, title:, class: css, data:, type: :submit do
      safe_join([icon, content_tag(:span, text)])
    end
  end

  def heroicon_brain
    <<~SVG
      <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M15.5 13a3.5 3.5 0 0 0 -3.5 3.5v1a3.5 3.5 0 0 0 7 0v-1.8" />
        <path d="M8.5 13a3.5 3.5 0 0 1 3.5 3.5v1a3.5 3.5 0 0 1 -7 0v-1.8" /><path d="M17.5 16a3.5 3.5 0 0 0 0 -7h-.5" /><path d="M19 9.3v-2.8a3.5 3.5 0 0 0 -7 0" />
        <path d="M6.5 16a3.5 3.5 0 0 1 0 -7h.5" />
        <path d="M5 9.3v-2.8a3.5 3.5 0 0 1 7 0v10" />
      </svg>
    SVG
  end

  def lucide_dice
    <<~SVG
      <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <rect x="4.5" y="4.5" width="15" height="15" rx="3" ry="3" stroke-linecap="round" stroke-linejoin="round"/>
        <circle cx="8.5" cy="8.5" r="1.25" fill="currentColor"/>
        <circle cx="15.5" cy="8.5" r="1.25" fill="currentColor"/>
        <circle cx="12" cy="12" r="1.25" fill="currentColor"/>
        <circle cx="8.5" cy="15.5" r="1.25" fill="currentColor"/>
        <circle cx="15.5" cy="15.5" r="1.25" fill="currentColor"/>
      </svg>
    SVG
  end

  def page_title
    content_for?(:page_title) ? content_for(:page_title) : DEFAULT_PAGE_TITLE
  end

  def page_description
    content_for?(:page_description) ? content_for(:page_description) : DEFAULT_PAGE_DESCRIPTION
  end

  def canonical_url
    "#{request.base_url}#{request.path}"
  end

  def page_url
    request.original_url
  end

  def page_image_url
    "#{request.base_url}/social-preview.png"
  end
end
