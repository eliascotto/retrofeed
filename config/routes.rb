Rails.application.routes.draw do
  root to: "home#index"

  # Health check for load balancers and uptime monitors
  get "up", to: "health#show", as: :rails_health_check

  # Search
  resource :search, only: [ :show ]

  # Login/Logout
  resources :sessions, only: [ :new, :create, :destroy ]

  # Password reset
  resource :password_reset, only: [ :new, :create, :edit, :update ]

  # Signup
  resources :users, only: [ :new, :create ]

  # Handle setup (after email confirmation)
  resources :handle_setups, only: [ :new, :create ]

  # Email confirmation
  resources :confirmations, only: [ :new, :create, :show, :edit, :update ]

  # Sites with nested subscription management
  resources :sites, only: [ :index, :show, :create ] do
    resource :subscription, only: [ :destroy ], controller: "subscriptions"
    resource :refresh, only: [ :create ], controller: "sites/refreshes"
  end

  # Articles with reading actions
  resources :articles, only: [ :show ] do
    scope module: :articles do
      resource :download, only: [ :create ]
    end

    member do
      post :random
      post :next
    end
  end

  # User article actions to configure state
  resources :user_articles, only: [], param: :article_id do
    member do
      post   :mark_read
      delete :mark_read, action: :mark_unread
      post   :remove
      post   :restore
    end
  end

  # User-curated article lists (using public_slug for shareable URLs)
  resources :lists, only: [ :index, :show ], param: :public_slug
  resources :lists, only: [ :create, :update, :destroy ]

  # Settings with nested sections
  resource :settings, only: [ :show ] do
    scope module: :settings do
      resource :account, only: [ :show ], controller: "accounts" do
        resource :email, only: [ :show, :update ], controller: "account/emails"
        resource :password, only: [ :show, :update ], controller: "account/passwords"
        resource :handle, only: [ :show, :update ], controller: "account/handles"
      end

      resource :appearance, only: [ :show ], controller: "appearances"
    end
  end

  # Error page
  resources :errors, only: [ :show ], param: :type

  # Internal API for async operations
  namespace :api do
    # Articles
    resources :articles, only: [] do
      member do
        post :refresh
        post :track_view
      end
    end

    # Read next list
    resource :read_next, only: [] do
      resources :list_articles, path: "articles",
        param: :article_id, only: [ :create, :destroy ]
    end
  end

  if Rails.env.development? || Rails.env.test?
    # Playground
    resource :playground, only: [ :show, :create ], controller: "playground" do
      scope module: "playground" do
        resources :fixtures, only: [ :index, :destroy ] do
          delete :destroy_all, on: :collection
        end
      end

      post :process_article, on: :collection
    end

    # Admin tools
    namespace :admin do
      resources :tasks, only: [ :index, :show ] do
        member do
          post :run
        end
      end
    end
  end

  # Lookbook page for development
  if Rails.env.development? && defined?(Lookbook)
    mount Lookbook::Engine, at: "/lookbook"
  end
end
