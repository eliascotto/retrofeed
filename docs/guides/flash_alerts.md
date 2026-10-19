# Flash Alerts

Flash messages are the brief toast notifications that appear at the top of the page and auto-dismiss after a few seconds. They are the standard way to communicate one-off feedback to the user — success confirmations, errors, warnings — from any layer of the application.

The system has four levels: `success`, `error`, `warning`, and `info` (default). Each maps to a distinct background color defined in [`flash.css`](../../app/assets/stylesheets/flash.css).

## How it works

The DOM anchor is a `<div id="flashes">` rendered in the main layout. Both server-side and client-side code append flash items into this container. Each item is animated to appear and then fade; a Stimulus controller removes it from the DOM once the animation ends.

The partial at [`layouts/shared/_flash.html.erb`](../../app/views/layouts/shared/_flash.html.erb) renders a single flash item and accepts two locals:
- `message` — the text to display
- `level` — one of `:success`, `:error`, `:warning`, `:info` (defaults to `:info`)

## From a Ruby controller (redirect)

Use Rails flash with the `notice:` or `alert:` shorthand, or set `flash[]` directly before redirecting.

```ruby
# :notice maps to the "success" level
redirect_to root_path, notice: "Logged in successfully"

# :alert maps to the "error" level
redirect_to new_session_path, alert: "Invalid email or password"
```

The `flash_level` helper in `ApplicationHelper` translates flash keys to levels:

| Flash key | Displayed level |
|---|---|
| `:notice`, `:success` | `success` |
| `:alert`, `:error` | `error` |
| `:warning` | `warning` |
| anything else | `info` |

## From a Ruby controller (re-render without redirect)

When re-rendering the current page (e.g. form validation failure), use `flash.now` so the message is available for that render only and not carried to the next request.

```ruby
def create
  if params[:email].blank?
    flash.now[:alert] = "Email is required"
    render :new, status: :unprocessable_entity
  end
end
```

## From a Turbo Stream response

When an action responds with a Turbo Stream, append the flash partial directly to the `flashes` container. This lets the page update without a full redirect while still showing feedback.

In a `.turbo_stream.erb` template:

```erb
<%= turbo_stream.append "flashes" do %>
  <%= render "layouts/shared/flash", message: "Site added", level: :success %>
<% end %>
```

See [`create.turbo_stream.erb`](../../app/views/sites/create.turbo_stream.erb) for a real example.

## From a background job or model (via Turbo Streams broadcast)

Long-running operations can push flashes to the user's browser over the Action Cable connection after the request has finished. Use `Turbo::StreamsChannel.broadcast_append_later_to` targeting the user's stream.

```ruby
Turbo::StreamsChannel.broadcast_append_later_to(
  "user_#{user.id}",
  target: "flashes",
  partial: "layouts/shared/flash",
  locals: { message: "Import complete", level: :success }
)
```

The `_later` variant enqueues the broadcast as a job, which avoids holding a database transaction open while waiting for Action Cable. Use it whenever broadcasting from inside a model callback or job.

See [`website.rb`](../../app/models/website.rb) for a working example of broadcasting an error flash after a background processing failure.

## From a JavaScript controller (Stimulus)

The global `window.showFlash` function defined in [`flash.js`](../../app/javascript/flash.js) creates and appends a flash item imperatively. Use it in Stimulus controllers when responding to fetch/XHR calls where a server-rendered Turbo Stream is not available.

```js
window.showFlash("Article saved", "success")
window.showFlash("Something went wrong", "error")
window.showFlash("Please wait before trying again", "warning")
window.showFlash("Refresh started")  // defaults to "info"
```

Signature: `showFlash(message, level = "info")`

Valid levels: `"success"`, `"error"`, `"warning"`, `"info"`.

## Choosing the right approach

| Situation | Approach |
|---|---|
| Controller redirects after a standard form | `redirect_to path, notice:` / `alert:` |
| Controller re-renders a form with errors | `flash.now[:alert] = ...` before `render` |
| Turbo Stream response (inline page update) | `turbo_stream.append "flashes"` in `.turbo_stream.erb` |
| Background job or async model callback | `Turbo::StreamsChannel.broadcast_append_later_to` |
| Stimulus controller handling a fetch response | `window.showFlash(message, level)` |
