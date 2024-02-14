# frozen_string_literal: true

module ProphetRatings
  class Gaussian
    def initialize(mean, stddev, rand_helper = -> { Kernel.rand })
      @mean = mean
      @stddev = stddev
      @valid = false
      @rand_helper = rand_helper
      @next = 0
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
