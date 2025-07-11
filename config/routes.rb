# frozen_string_literal: true

Rails.application.routes.draw do
  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'
  devise_for :users, only: [:sessions]
  get 'matchups/new'
  get 'matchups/submit'
  get 'games/index'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  mount GoodJob::Engine => 'good_job'

  root "team_seasons#ratings"
  resources :games, only: [:index, :show] do
    collection do
      get :schedule
      get :betting
    end
  end
  resource :matchup, only: [:show] do
    post :submit, on: :collection
  end
  resources :teams, param: :slug, only: [:index, :show]
end
