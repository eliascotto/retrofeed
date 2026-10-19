# Rails: What Goes Where

> Core principle: **fat models, skinny controllers, dumb views** — and Service Objects for everything in between.

---

## Core MVC

### Model — `app/models/`

Business logic and data rules. The model owns anything that relates to data validity, state, or domain behaviour.

**Put here:**
- Validations
- Associations
- Scopes and queries
- Business-level methods

**Keep out:** HTTP/params awareness, sending emails, talking to external APIs, rendering HTML. If a method needs more than one other model — extract to a Service Object.

```ruby
# Good model method — pure business logic
def transfer_to(target_account, amount)
  raise InsufficientFunds unless balance >= amount
  transaction do
    decrement!(:balance, amount)
    target_account.increment!(:balance, amount)
  end
end
```

---

### Controller — `app/controllers/`

Orchestration only — no business logic. Single job: receive HTTP input, call the right model/service, hand off to view. If your action is 20+ lines, something business-related crept in — extract to a Service Object.

**Put here:**
- Parse params
- Call model/service
- Set `@instance` vars
- Redirect / render

```ruby
def create
  result = CheckoutService.call(current_user, checkout_params)
  if result.success?
    redirect_to order_path(result.order)
  else
    @errors = result.errors
    render :new
  end
end
```

---

### View — `app/views/`

Presentation only — no queries. Never call `.where`, `.find`, or `.count` inside a view. Those belong in the controller (`@vars`) or model (scopes). Use helpers for formatting, presenters for complex display logic.

**Put here:**
- HTML + ERB/Haml
- Conditionals on display
- Calls to helpers/presenters

**Never:** ActiveRecord queries.

```erb
<%# Bad — query in view %>
<% Order.where(user: current_user).each do |o| %>

<%# Good — use what controller set %>
<% @orders.each do |order| %>
  <%= order.total_formatted %>
<% end %>
```

---

## Supporting Layers

### Service Object — `app/services/`

Multi-model operations or external calls. Convention: one public method (`call`), returns a result object. Keeps controllers skinny without bloating models.

Common patterns: Command (`UserSignup.call`), Query (`RecentActiveUsers.call`), Form Object wrapping params.

**Put here:**
- Checkout, sign-up flows
- API integrations
- Anything crossing 2+ models

```ruby
class UserSignupService
  def self.call(params)
    user = User.new(params)
    return failure(user.errors) unless user.save
    WelcomeMailer.welcome(user).deliver_later
    success(user)
  end
end
```

---

### Job — `app/jobs/`

Async and background work. Anything that can fail, retry, or is slow goes in a job. Enqueue from controllers or service objects — never from models in `after_save` callbacks.

**Put here:**
- Emails, notifications
- Slow 3rd-party calls
- Bulk operations

```ruby
class InvoiceGenerationJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    InvoiceService.generate(order)
  end
end

# Called from controller/service:
InvoiceGenerationJob.perform_later(order.id)
```

---

### Concern — `app/models/concerns/` and `app/controllers/concerns/`

Shared behaviour across classes. Only extract to a concern when the same behaviour genuinely appears in 3+ places. Don't reach for concerns to hide complexity — use Service Objects instead.

**Put here:**
- `Taggable`, `Publishable` model mixins
- Auth checks used in 3+ controllers

```ruby
module Publishable
  extend ActiveSupport::Concern

  included do
    scope :published, -> { where(status: 'published') }
  end

  def publish!
    update!(status: 'published', published_at: Time.current)
  end
end
```

---

### Helper — `app/helpers/`

View formatting utilities. Good for: formatting (dates, money, truncation), generating small HTML fragments. For objects with complex display logic (different states, many view methods), use a Presenter (PORO wrapping the model) instead.

**Put here:**
- Format dates, currency
- Build HTML snippets

```ruby
# app/helpers/orders_helper.rb
def format_price(cents)
  number_to_currency(cents / 100.0)
end
```

---

### Mailer — `app/mailers/`

Email composition. Mailers are like controllers for email. Logic for building the email lives in the mailer. The actual content lives in `app/views/user_mailer/`. Enqueue via jobs — don't call `deliver_now` in controllers for user-facing actions.

```ruby
class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    mail(to: @user.email, subject: 'Welcome!')
  end
end
# view: app/views/user_mailer/welcome.html.erb
```

---

## Config & Infrastructure

### Routes — `config/routes.rb`

URL to controller mapping. Use resourceful routing (`resources :orders`) by default. Use `namespace` for API versioning. Use `scope` for URL prefixes without module nesting. Use `constraints` for subdomain routing or format restrictions. No business logic here.

```ruby
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :orders, only: [:index, :show, :create]
    end
  end

  resources :users do
    member { post :ban }
    collection { get :admins }
  end
end
```

---

### Migration — `db/migrate/`

Schema changes only — immutable once run. Migrations define what the DB looks like, not how data moves. Never rely on models in a migration (model code changes; old migrations don't). For backfilling data, write a separate Rake task or script that you run after the migration.

**Never edit an old migration** — create a new one.

```ruby
class AddStatusToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :status, :string, default: 'pending', null: false
    add_index  :orders, :status
  end
end
```

---

### Initializer — `config/initializers/`

Boot-time setup for gems and services. Runs once when Rails starts. Use for: configuring gems, setting up clients (Stripe, Redis), registering global defaults. Keep them small — large initializers slow boot time.

```ruby
# config/initializers/stripe.rb
Stripe.api_key = Rails.application.credentials.stripe[:secret_key]

# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end
```

---

## Decision Rule (covers 80% of cases)

| Question | Answer |
|---|---|
| Does it touch the DB or enforce business rules? | Model (or Service Object if it crosses models) |
| Does it coordinate an HTTP request? | Controller |
| Does it format data for display? | View / Helper / Presenter |
| Does it need to run later or retry? | Job |
| Does it configure a gem at boot? | Initializer |

**Most common mistakes:** queries in views, business logic in controllers, overusing `after_save` callbacks where a Service Object + Job would be clearer.