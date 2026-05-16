# frozen_string_literal: true

namespace :venue do
  desc 'Enrich game venue classifications from manual overrides and Sports Reference team schedules'
  task enrich: :environment do
    scope = ENV['SEASON'].present? ? Game.joins(:season).where(seasons: { year: ENV.fetch('SEASON').to_i }) : Game.all

    Importer::GameVenueEnricher.new(scope).call
  end

  desc 'Report venue classification coverage and list unknown games'
  task coverage: :environment do
    scope = ENV['SEASON'].present? ? Game.joins(:season).where(seasons: { year: ENV.fetch('SEASON').to_i }) : Game.all
    counts = scope.group(:venue_type).count

    %w[home neutral unknown].each do |venue_type|
      puts "#{venue_type}: #{counts.fetch(venue_type, 0)}"
    end

    puts "\nUnknown games:"
    scope.where(venue_type: 'unknown').includes(:season).order(:start_time).find_each do |game|
      puts "#{game.start_time.to_date} | #{game.away_team_name} vs #{game.home_team_name} | venue_type: #{game.venue_type}"
    end
  end
end
