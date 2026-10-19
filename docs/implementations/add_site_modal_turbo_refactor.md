# Add Site Modal — Turbo Streams Refactor

## Background

Adding a site is currently a JSON-API + polling flow. The Stimulus controller in
[app/javascript/controllers/add_site_modal_controller.js](../../app/javascript/controllers/add_site_modal_controller.js)
POSTs JSON to `Api::SitesController#create`, receives a `job_id`, and polls
`/api/sites/:job_id/status` every 2 seconds until the background pipeline
finishes. On the success path it calls `Turbo.visit(..., { action: "replace" })`
as a fallback because the broadcast in
[app/controllers/concerns/subscription_broadcaster.rb](../../app/controllers/concerns/subscription_broadcaster.rb)
*sometimes* arrives, but the modal can't trust it.

This duplicates work the Hotwire stack already does well. It also conflicts with
the project guideline ("vanilla Rails, thin controllers, rich models" — see
[AGENTS.md](../../AGENTS.md)) by routing a normal user-initiated create through
a side-channel JSON API meant for "internal async operations."

The refactor moves submission and feedback onto Turbo Streams, deletes the
polling endpoint, and shrinks the Stimulus controller to a UI-only role.

## Goals

1. The modal submits via a normal Rails `form_with` and a `text/vnd.turbo-stream.html`
   response. No `fetch`, no `job_id`, no client polling.
2. Status feedback (pending / crawling / extracting / completed / failed) reaches
   the UI via per-card Turbo Stream broadcasts, keyed by `dom_id(website)`.
3. `Api::SitesController#create` and `#status` are deleted. The other endpoints
   under `namespace :api` are out of scope.
4. The Stimulus controller drops from ~196 lines to ~40 — open/close, focus,
   and a single `turbo:submit-end` listener. No business logic.

## Non-goals

- Do not change `ProcessWebsiteJob` or `CrawlArchiveJob` internals. Only the
  *signaling* layer changes — what they broadcast and when.
- Do not migrate other consumers of `namespace :api` (`progress`, `pending_jobs`,
  `articles_status`, `refresh`). Each is a separate decision and at least
  `progress` represents a real polling need (per-article fill rate during
  batch fetch).
- Do not change the Website schema. `processing_status` already covers the
  states the UI needs.

## Current flow (for reference)

```
Modal submit (JS)
  └── POST /api/sites           Api::SitesController#create
        └── ProcessWebsiteJob.perform_later
              └── CrawlArchiveJob
                    ├── Website.find_or_create_by(domain:)
                    ├── website.processing_status = "extracting"
                    ├── extract + create articles
                    ├── handle_subscription(user_id, website)
                    │     └── broadcast_replace_to "user_{id}" target: "main-content-body"
                    └── enqueue batch content jobs

Modal (parallel)
  └── GET /api/sites/{job_id}/status   poll every 2s
        └── reads SolidQueue::Job.find_by(active_job_id:)
              ├── pending  → keep polling
              ├── processing  → keep polling
              ├── completed  → showToast + Turbo.visit(replace)
              └── failed  → showToast(error)
```

The site list update is *technically* delivered by the broadcast, but the
`Turbo.visit` fallback is what makes the UX feel reliable today. We're
replacing both with one mechanism.

## Target flow

```
Modal submit (form_with, turbo-stream)
  └── POST /sites               SitesController#create
        ├── current_user.subscribe_to_url(url)
        │     ├── validate + normalize URL
        │     ├── Website.find_or_create_by!(domain:, processing_status: "pending")
        │     ├── subscriptions.find_or_create_by!(website:)
        │     └── ProcessWebsiteJob.perform_later(url, user.id)
        └── render turbo_stream:
              ├── prepend "sites/site_card" into "#sites-list"
              ├── replace "shared/add_site_modal" (closed + reset)
              └── append "shared/toast" into "#toasts"

Background pipeline (unchanged shape, new broadcasts)
  └── CrawlArchiveJob updates website.processing_status
        └── Website#after_update_commit broadcasts
              replace dom_id(website) → "sites/site_card" to each subscriber's stream

Failure
  └── CrawlArchiveJob#mark_website_failed
        └── status = "failed", processing_error_message set
              └── same after_update_commit broadcasts the failed-state card
                  AND appends a toast frame
```

The pending Website row exists from the moment the form succeeds, which is
what gives every subsequent broadcast a stable target (`dom_id(website)`).

## File-by-file changes

### Routes — [config/routes.rb](../../config/routes.rb)

Add `:create` to the HTML resource and remove it from the API namespace along
with the polled `status` member route.

```ruby
# Sites with nested subscription management
resources :sites, only: [ :index, :show, :create ] do
  resource :subscription, only: [ :destroy ], controller: "subscriptions"
end

# Internal API for async operations
namespace :api do
  resources :sites, only: [ :index ] do
    member do
      post :refresh
      get :articles_status
      # remove: get :status, path: "status/:job_id"
    end
    collection do
      get :progress
      get :pending_jobs
    end
  end
  # ... unchanged ...
end
```

### Domain method — `app/models/user.rb`

Add `User#subscribe_to_url`. This is where the conflict check, eager Website
creation, and job enqueue live. The controller becomes one line of business
logic.

```ruby
class User < ApplicationRecord
  AlreadySubscribedError = Class.new(StandardError)

  def subscribe_to_url(raw_url)
    normalized = UrlUtils.validate_and_normalize_url(raw_url)
    domain = UrlUtils.extract_domain(normalized)

    if subscriptions.joins(:website).exists?(websites: { domain: })
      raise AlreadySubscribedError, "You are already subscribed to #{domain}"
    end

    Website.transaction do
      website = Website.find_or_create_by!(domain:) do |w|
        w.name = domain
        w.processing_status = "pending"
      end
      subscriptions.find_or_create_by!(website:)
      ProcessWebsiteJob.perform_later(normalized, id)
      website
    end
  end
end
```

Notes:
- `find_or_create_by!` handles the case where another user already has the
  Website crawled; we only create the Subscription in that case and skip the
  job. The current `Api::SitesController#create` does the same conflict check,
  just in the controller — we move it into the model.
- Actually reconsider that: if the Website already exists and is `completed`,
  we should NOT enqueue another `ProcessWebsiteJob`. Branch:

```ruby
website = Website.find_or_create_by!(domain:) do |w|
  w.name = domain
  w.processing_status = "pending"
end
subscriptions.find_or_create_by!(website:)
ProcessWebsiteJob.perform_later(normalized, id) if website.processing_status_changed_to_pending?
website
```

  Use `previously_new_record?` after the find_or_create — only enqueue when
  this is a brand-new Website row.

### Controller — `app/controllers/sites_controller.rb`

Add `create`. Keep it thin per
[STYLE.md](../../STYLE.md).

```ruby
class SitesController < ApplicationController
  # ... existing index, show ...

  def create
    @website = current_user.subscribe_to_url(site_params[:url])

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to sites_path, notice: "Adding site..." }
    end
  rescue UrlUtils::InvalidUrlError, User::AlreadySubscribedError, ActiveRecord::RecordInvalid => e
    @error_message = e.message

    respond_to do |format|
      format.turbo_stream { render :create_error, status: :unprocessable_entity }
      format.html { redirect_to sites_path, alert: e.message }
    end
  end

  private
    def site_params
      params.require(:site).permit(:url)
    end
end
```

The two Turbo Stream views:

`app/views/sites/create.turbo_stream.erb`:
```erb
<%= turbo_stream.prepend "sites-list" do %>
  <%= render "sites/site_card", website: @website %>
<% end %>

<%= turbo_stream.replace "add-site-modal" do %>
  <%= render "layouts/shared/add_site_modal" %>
<% end %>

<%= turbo_stream.append "toasts" do %>
  <%= render "shared/toast", message: "Adding #{@website.domain}…", level: :info %>
<% end %>
```

`app/views/sites/create_error.turbo_stream.erb`:
```erb
<%= turbo_stream.replace "add-site-modal-form-body" do %>
  <%= render "layouts/shared/add_site_modal_form", error: @error_message %>
<% end %>
```

The error stream replaces only the form body (a new partial extracted in the
view step), leaving the dialog open so the user sees inline feedback exactly
as today.

### Website model — broadcast on status change

In [app/models/website.rb](../../app/models/website.rb), add a per-card
broadcast that fires on every `processing_status` transition. We do *not* use
`broadcasts_to` because the target stream is per-subscriber, not per-website.

```ruby
class Website < ApplicationRecord
  after_update_commit :broadcast_card_to_subscribers,
    if: :saved_change_to_processing_status?

  private
    def broadcast_card_to_subscribers
      subscriptions.includes(:user).find_each do |subscription|
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_#{subscription.user_id}",
          target: ActionView::RecordIdentifier.dom_id(self),
          partial: "sites/site_card",
          locals: { website: self, current_user: subscription.user }
        )

        if processing_status == "failed"
          Turbo::StreamsChannel.broadcast_append_to(
            "user_#{subscription.user_id}",
            target: "toasts",
            partial: "shared/toast",
            locals: {
              message: "Failed to add #{domain}: #{processing_error_message}",
              level: :error
            }
          )
        end
      end
    end
end
```

For sites with many subscribers this fires N broadcasts per transition. Since
`processing_status` only changes a handful of times across a crawl
(`pending → crawling → extracting → completed/failed/partial`), the volume is
bounded. If it becomes a problem, batch via `find_in_batches` and a single
`broadcast_later_to` call per batch.

### View extraction — `app/views/sites/`

Today [_list.html.erb](../../app/views/sites/_list.html.erb) inlines each site
row inside the `each` loop. Extract:

`app/views/sites/_site_card.html.erb` — a single site card. Must wrap with the
exact dom_id the broadcast targets:

```erb
<%= tag.div id: dom_id(website),
            class: site_card_classes(website),
            data: {
              website_id: website.id,
              site_processing: website.processing?,
              processing_status: website.processing_status
            } do %>
  <% case website.processing_status %>
  <% when "pending", "crawling" %>
    <%= render "sites/site_card_skeleton", website: website %>
  <% when "extracting" %>
    <%= render "sites/site_card_extracting", website: website %>
  <% when "failed" %>
    <%= render "sites/site_card_failed", website: website %>
  <% else %>
    <%= render "sites/site_card_default", website: website %>
  <% end %>
<% end %>
```

Add `Website#processing?` if it doesn't exist:
```ruby
def processing?
  %w[pending crawling extracting].include?(processing_status)
end
```

`_list.html.erb` collapses to:
```erb
<%= render partial: "sites/site_card", collection: @websites, as: :website %>
```

### Modal — [_add_site_modal.html.erb](../../app/views/layouts/shared/_add_site_modal.html.erb)

Convert the inner `<form>` to `form_with`. Wrap the form body in its own
target so the error stream can replace just that piece without resetting the
dialog state.

```erb
<dialog id="add-site-modal" class="modal"
        data-controller="add-site-modal"
        data-action="modal:open@window->add-site-modal#open
                     turbo:submit-end->add-site-modal#onSubmitEnd">
  <div class="modal-box">
    <%= form_with url: sites_path, scope: :site, data: { turbo_frame: "_top" } do |f| %>
      <div id="add-site-modal-form-body">
        <%= render "layouts/shared/add_site_modal_form", error: nil %>
      </div>
    <% end %>
  </div>
</dialog>
```

`app/views/layouts/shared/_add_site_modal_form.html.erb`:
```erb
<%= form_with url: sites_path, scope: :site, data: { turbo_frame: "_top" },
              builder: ApplicationFormBuilder do |f| %>
  <%= f.url_field :url,
        required: true,
        autofocus: true,
        placeholder: "https://example.com",
        data: { add_site_modal_target: "urlInput" } %>

  <% if error.present? %>
    <p data-add-site-modal-target="urlError" class="text-error text-sm">
      <%= error %>
    </p>
  <% end %>

  <button type="submit" class="btn btn-primary">
    <span data-loading-hide>Add Website</span>
    <span data-loading-show class="loading loading-spinner"></span>
  </button>
<% end %>
```

Removed:
- `data-add-site-modal-api-url-value`
- `data-add-site-modal-status-url-value`
- `data-add-site-modal-csrf-token-value` (Rails handles CSRF on real forms)
- Manual `submitText`/`submitLoading` targets — replaced by Turbo's
  `aria-busy` attribute on the submit button. One global CSS rule:
  `[aria-busy="true"] [data-loading-hide] { display: none; }` and inverse for
  `[data-loading-show]`.

### Stimulus controller — `add_site_modal_controller.js`

Replace 196 lines with ~35:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["urlInput"]

  connect() {
    window.openAddSiteModal = () => this.open()
  }

  open() {
    this.element.showModal()
    requestAnimationFrame(() => this.urlInputTarget?.focus())
  }

  close() {
    this.element.close()
  }

  onSubmitEnd(event) {
    if (event.detail.success) {
      this.close()
    }
  }
}
```

Deleted methods: `submit`, `enableSubmit`, `showError`, `pollJobStatus`,
`resetForm`, `disconnect` cleanup. Reset is now automatic — the success
turbo_stream replaces the entire modal partial with a fresh one.

### Toast — server-rendered

Today `window.showToast` is a JS-only side channel. After this refactor toasts
arrive as Turbo Stream `append` frames, keeping the success and failure paths
symmetric (controller success appends; broadcast failure appends).

In [application.html.erb](../../app/views/layouts/application.html.erb), make
sure there's a `<div id="toasts">` container near the top of `<body>`. Create
`app/views/shared/_toast.html.erb` with auto-dismiss via a small Stimulus
controller (or keep the existing `window.showToast` *display* logic and have
the partial trigger it via `data-controller="toast"` on connect).

Keep `window.showToast` in the codebase only for purely client-driven cases
(e.g. network failure on a different feature). The add-site flow stops calling
it directly.

### Drop the API endpoints

In [api/sites_controller.rb](../../app/controllers/api/sites_controller.rb):
- Delete `#create`
- Delete `#status`
- Delete `#extract_error_message` (only `#status` uses it)
- Keep `#index`, `#progress`, `#pending_jobs`, `#articles_status`, `#refresh`

The `index` JSON endpoint remains because some other client may use it; if a
quick grep shows no callers, delete it too in the cleanup PR.

## Testing

### Files to update

- **Update** [test/controllers/api/sites_controller_test.rb](../../test/controllers/api/sites_controller_test.rb)
  — delete the entire `#create` test group and the `#status` test group.
  Keep `#progress`, `#pending_jobs`, `#articles_status`, `#refresh` cases.

- **Add** `test/controllers/sites_controller_create_test.rb`:
  - submits valid URL → returns turbo_stream, response includes site_card and
    closed modal frames, `ProcessWebsiteJob` enqueued, Website created with
    `processing_status: "pending"`, Subscription created.
  - submits invalid URL → 422 turbo_stream, modal form replaced with inline
    error, no job enqueued.
  - submits already-subscribed domain → 422 turbo_stream with the conflict
    error, no duplicate Subscription, no job enqueued.
  - submits URL whose Website already exists in `completed` state →
    Subscription created, NO `ProcessWebsiteJob` enqueued, success
    turbo_stream rendered.

- **Add** `test/models/user_subscribe_to_url_test.rb`:
  - creates Website + Subscription + enqueues job
  - raises `User::AlreadySubscribedError` on duplicate
  - raises `UrlUtils::InvalidUrlError` on bad input
  - skips job when Website already crawled

- **Add** `test/models/website_broadcast_test.rb`:
  - assert `Turbo::StreamsChannel` receives `broadcast_replace_to` with the
    right stream name and target on each `processing_status` transition.
  - assert toast append fires once on `failed` transition, not on others.
  - use `assert_broadcasts` or `Turbo::StreamsChannel.stub(:broadcast_replace_to)`.

- **Update** `test/jobs/crawl_archive_job_test.rb`:
  - Website may already exist with `processing_status: "pending"` when the
    job starts. Existing `find_or_create_by(domain:)` handles this, but add
    an explicit assertion that the job updates an existing pending row
    rather than creating a new one.
  - Assert `processing_status` transitions: `pending → extracting →
    completed`. The transitions trigger the broadcast hook — assert at least
    one `broadcast_replace_to` call (or stub them out for isolation).

- **Add** `test/system/add_site_test.rb`:
  - Visit `/sites`, click "Add site", fill URL, submit.
  - Assert pending card appears in `#sites-list` immediately.
  - `perform_enqueued_jobs` to drive the pipeline.
  - Assert card morphs to completed state (Capybara waits naturally).
  - Submit invalid URL → assert inline error appears, modal stays open.

### Tests that should NOT change

- `test/jobs/process_website_job_test.rb` — interface unchanged.
- `test/controllers/sites_controller_test.rb` (index/show) — unchanged.

## Risks and edge cases

1. **Pending Websites visible in queries.** `Website.where(processing_status: "pending")`
   rows now exist. The `visible` scope only filters `failed`. Audit other
   places that enumerate Websites — search, admin, settings exports — and
   decide whether they should also exclude `pending`. If yes, broaden the
   scope or add `Website.scope :ready, -> { where(processing_status: %w[completed partial]) }`.

2. **User reloads before broadcast subscription is established.** The form
   redirects on non-Turbo requests, but if the WebSocket hasn't connected
   when the broadcast fires, the user misses the live update. Recovery is
   automatic on next page load because the row exists with its current
   status — the `_site_card` partial renders the right state from the DB.
   No additional handling needed.

3. **Many subscribers per Website.** Broadcasts fan out per-subscriber.
   Bounded by status transitions (~5 per crawl), but if a popular domain
   gets thousands of subscribers, prefer `broadcast_later_to` to push the
   fanout into a job. Defer this until measurement shows it matters.

4. **Race between transactional commit and broadcast.** `after_update_commit`
   runs after the DB commit, so the partial render reads the new state
   correctly. Verify there's no `after_update` (without `_commit`) being
   used in nearby model code that could fire prematurely.

5. **`SubscriptionBroadcaster#broadcast_user_subscriptions` becomes
   redundant.** With per-card broadcasts working, the full
   `#main-content-body` replace is no longer load-bearing. Don't remove it
   in this PR — leave it as a coarse refresh and audit in a follow-up after
   a few days of dev usage. If removed too eagerly we lose the home-page
   update path (home renders a different partial than sites/index).

6. **Tests that stub `ProcessWebsiteJob`.** Tests that previously asserted
   "job enqueued" via the API endpoint now need to assert it via the new
   controller and via `User#subscribe_to_url`. Grep for `ProcessWebsiteJob`
   in `test/` to find all touch points.

## PR breakdown

Split to keep each PR independently revertible.

1. **Eager Website + domain method.** Add `User#subscribe_to_url`, add
   `Website#processing?`, change `Api::SitesController#create` to delegate
   to the new method. No view changes. API still works. Tests for the new
   model method.

2. **Per-card broadcast + view extraction.** Extract `_site_card` partial
   with all status variants. Add `Website#after_update_commit` broadcast
   hook. Polling JS still in place; the broadcast updates are redundant
   but harmless.

3. **HTML create endpoint + modal form.** Add `SitesController#create`,
   convert modal to `form_with`, slim the Stimulus controller. Both the
   API and HTML endpoints work in parallel — flip the modal to the new
   path.

4. **Delete API endpoints.** Remove `Api::SitesController#create`,
   `#status`, `#extract_error_message`. Remove polling code from
   `add_site_modal_controller.js`. Update API controller tests. This is
   the breaking change PR.

5. **(Follow-up, not part of this work.)** Audit
   `SubscriptionBroadcaster#broadcast_user_subscriptions` for removal.
   Audit other `Website` queries for pending-row exclusion if needed.

## Definition of done

- Submitting a valid URL adds a pending card in <100ms (no network round trip
  beyond the form POST), and the card transitions live as the pipeline runs.
- Submitting an invalid or duplicate URL keeps the modal open with an inline
  error and no flash redirect.
- Failures during crawling produce a failed-state card and a toast, both
  delivered by broadcast.
- `bin/ci` passes (Rubocop, Brakeman, all test suites including the new
  system test).
- `app/javascript/controllers/add_site_modal_controller.js` is under 50
  lines and contains no `fetch`, no `setInterval`, no error handling.
- `Api::SitesController` no longer defines `create` or `status`.
