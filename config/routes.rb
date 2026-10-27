# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :admin do
    resources :offseason_readiness_reviews, only: %i[index create show] do
      post :activate_season, on: :member
      post :activate_model, on: :member
    end
    resources :preseason_publications, only: %i[index create show] do
      get :progress, on: :member
      post :retry_preview, on: :member
      post :select_model, on: :collection
      post :publish, on: :member
    end
    resources :schedule_refresh_runs, only: %i[index create show] do
      post :retry, on: :member
      post :defer, on: :collection
      resources :game_schedule_reviews, only: %i[show update]
      resources :game_scoring_reviews, only: %i[show update] do
        post :preview, on: :member
      end
    end
    get 'offseason_setup', to: 'offseason_setups#show', as: :offseason_setup
    post 'offseason_setup', to: 'offseason_setups#create'
    resources :cbbd_review_runs, only: %i[index create show update] do
      post :compare, on: :member
      post :apply, on: :member
    end
    resource :prediction_evaluation, only: :show
    resources :coaching_reviews, only: %i[index show update] do
      member do
        post :discover
        post :candidate
      end
    end
    resources :departure_batches, only: %i[index create show update] do
      member do
        post :acquire
        post :recover
        post :correct
        patch :publish, to: 'departure_validations#publish'
        post :revalidate, to: 'departure_validations#revalidate'
        get :progress, to: 'departure_validations#progress'
        patch :coverage
        get :source
      end
    end
    resources :recruiting_batches, only: %i[index create show update] do
      patch :publish, on: :member
      get :source, on: :member
    end
  end

  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'
  devise_for :users, only: [:sessions]
  get 'matchups/new'
  get 'matchups/submit'
  get 'games/index'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  authenticate :user, ->(user) { user.admin? } do
    mount GoodJob::Engine => 'good_job'
  end

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
  resources :conferences, only: %i[index show]
end
