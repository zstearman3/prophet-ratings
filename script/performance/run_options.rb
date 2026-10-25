# frozen_string_literal: true

require 'optparse'

module OffseasonPerformance
  # Parses the small standalone CLI without loading Rails or creating Docker resources.
  module RunOptions
    def self.parse(argv)
      options = { scale: 1, output: 'tmp/offseason-benchmark/results.json', assert: false }
      parser = parser(options)
      parser.parse!(argv)
      validate(options, argv)
      options
    end

    def self.parser(options)
      parser = OptionParser.new('Usage: bin/benchmark-offseason [--scale 1|2] [--output PATH] [--assert] [--scenario NAME]')
      data_options(parser, options)
      mode_options(parser, options)
      help_option(parser)
      parser
    end

    def self.data_options(parser, options)
      parser.on('--scale N', Integer) { |value| options[:scale] = value }
      parser.on('--output PATH') { |value| options[:output] = value }
    end

    def self.mode_options(parser, options)
      parser.on('--scenario NAME', Runner::SCENARIOS) { |value| options[:scenario] = value }
      parser.on('--assert') { options[:assert] = true }
    end

    def self.help_option(parser)
      parser.on('-h', '--help') do
        puts parser
        exit
      end
    end

    def self.validate(options, argv)
      scale = options.fetch(:scale)
      empty = argv.empty?
      raise ArgumentError, 'scale must be 1 or 2' unless [1, 2].include?(scale)
      raise ArgumentError, 'unexpected arguments' unless empty
    end
  end
end
