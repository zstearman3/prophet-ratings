# frozen_string_literal: true

module Admin
  # Escaped descriptions distinguish reported team totals from shooting arithmetic.
  module GameScoringReviewsHelper
    def scoring_choice_label(side, total)
      score, stats = side.values_at(:score, :stats)
      labels = { stats[:points] => 'Reported box points', score => 'Reported game score (recommended)' }
      tag.span("#{labels.fetch(total, 'Shooting arithmetic')}: #{total}")
    end

    def scoring_arithmetic(side)
      two, three, free = side.fetch(:stats).values_at(:two_pt_made, :three_pt_made, :free_throws_made)
      tag.span("2 × #{two} + 3 × #{three} + #{free}")
    end
  end
end
