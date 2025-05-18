# frozen_string_literal: true

module ApplicationHelper
  def icon_button(form, text:, icon_svg:, title:, **options)
    name  = options.delete(:name)
    value = options.delete(:value)
    css   = options.delete(:class)
    data  = options.delete(:data)

    icon = icon_svg.respond_to?(:html_safe) ? icon_svg.html_safe : icon_svg

    form.button name:, value:, title:, class: css, data:, type: :submit do
      "#{icon}<span>#{text}</span>".html_safe
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
end
