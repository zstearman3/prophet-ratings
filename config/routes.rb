# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :admin do
    resources :preseason_publications, only: %i[index create show] do
      post :select_model, on: :collection
      post :publish, on: :member
    end
    resources :schedule_refresh_runs, only: %i[index create show] do
      post :retry, on: :member
      post :defer, on: :collection
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
        patch :publish
        get :source
      end
    end
    resources :recruiting_batches, only: %i[index create show update] do
      patch :publish, on: :member
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
