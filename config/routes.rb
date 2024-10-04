Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :entries do
        collection do
          get "entries_by_budget_with_default_categories"
        end
      end
      resources :tags do
        collection do
          get 'default_tags'
        end
      end
      resources :budgets
      resources :users do
        collection do
          get 'show_by_email'
        end
      end
      resources :categories do
        collection do
          get 'default'
        end
      end
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
