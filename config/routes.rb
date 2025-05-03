# frozen_string_literal: true

Rails.application.routes.draw do
  get 'games/index'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  mount GoodJob::Engine => 'good_job'

  root "team_seasons#ratings"

  get 'game_prediction', to: "predictions#game"
  get 'game_simulation', to: "simulations#game"
  resources :games, only: [:index, :show]

  resources :teams, param: :slug, only: [:index, :show]
end
