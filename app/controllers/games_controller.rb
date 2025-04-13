class GamesController < ApplicationController
  def index
    @games = Game.order(start_time: :desc).limit(20)
  end
end
