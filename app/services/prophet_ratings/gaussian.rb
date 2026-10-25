# frozen_string_literal: true

module ProphetRatings
  class Gaussian
    RANDOM = -> { Kernel.rand }

    def initialize(mean, stddev, rand_helper = RANDOM)
      @mean = mean
      @stddev = stddev
      @next = 0
      @valid = false
      @rand_helper = rand_helper
    end

    def rand
      if @valid
        @valid = false
        @next
      else
        @valid = true
        x, y = gaussian(@mean, @stddev, @rand_helper)
        @next = y
        x
      end
    end

    private

    def gaussian(mean, stddev, rand)
      theta = 2 * Math::PI * rand.call
      rho = Math.sqrt(-2 * Math.log(1 - rand.call))
      scale = stddev * rho
      x = mean + (scale * Math.cos(theta))
      y = mean + (scale * Math.sin(theta))
      [x, y]
    end
  end
end
