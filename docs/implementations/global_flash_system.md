# Global flash/toast system

## Context

The toast/flash messaging in this app is half-migrated and broken:

- `app/views/sites/create.turbo_stream.erb:6` and `app/models/website.rb:379` both render a `shared/_toast` partial that does not exist — `Sites#create` blows up with `ActionView::MissingTemplate`.
- The layout at `app/views/layouts/application.html.erb:79-93` renders flashes inline using DaisyUI `.alert` classes (tech debt per `AGENTS.md`).
- Two competing JS controllers exist: `toast_controller.js` (event-driven, DaisyUI) and `flash_controller.js` (5s setTimeout). Neither is consistent with the other or with the half-migrated server callsites.
- A `flash.css` file (`app/assets/stylesheets/flash.css`) already defines `.flash` / `.flash__inner` with an `appear-then-fade` animation, but nothing renders these classes.

We want a single, simple system that:

1. Works for server-rendered flashes set by controllers (`flash[:notice] = "..."`) on full-page navigations.
2. Works for Turbo Stream broadcasts from models / jobs (e.g. `Website#broadcast_to_subscribers` queueing an "Adding domain…" or error message).
3. Has built-in lifespan via CSS animation + `animationend`, no JS timers.
4. Uses modern CSS in line with the project's "DaisyUI is tech debt" direction.

## Approach

A single shared partial backed by a single tiny Stimulus controller and the existing `flash.css` (extended with level modifiers). One container in the layout that is both the initial render target and the Turbo Stream broadcast target. Old toast/flash plumbing is removed.

### 1. Partial: `app/views/shared/_flash.html.erb`

Renders one flash message. Locals: `message:` (String), `level:` (Symbol, one of `:info`, `:success`, `:warning`, `:error`; default `:info`).

```erb
<%# locals: (message:, level: :info) %>
<div class="flash__item flash__item--<%= level %>"
     data-controller="element-removal"
     data-action="animationend->element-removal#remove">
  <%= message %>
</div>
```

Why no outer `.flash` wrapper per item: `flash.css` currently uses `.flash` as a single fixed-position container. We move fixed positioning onto the **container** in the layout (so multiple items stack), and `.flash__item` is each pill. See CSS section.

### 2. Container partial: `app/views/shared/_flashes.html.erb`

Renders the container plus initial flash messages from the Rails `flash` hash. Used by the layout. Also serves as the Turbo Stream target id (`flashes`).

```erb
<div id="flashes" class="flashes">
  <% flash.each do |type, message| %>
    <%= render "shared/flash", message: message, level: flash_level(type) %>
  <% end %>
</div>
```

A small helper `flash_level(type)` in `app/helpers/application_helper.rb` maps Rails' default keys (`notice`, `alert`) plus custom keys (`success`, `error`, `warning`, `info`) to one of the four canonical levels:

```ruby
def flash_level(type)
  case type.to_sym
  when :notice, :success then :success
  when :alert, :error    then :error
  when :warning          then :warning
  else                        :info
  end
end
```

### 3. Layout integration: `app/views/layouts/application.html.erb`

Replace the existing toast block (lines 79–93) with:

```erb
<%= render "shared/flashes" %>
```

Remove the inline DaisyUI alert markup and the `#toast-container` div entirely.

### 4. Stimulus controller: `app/javascript/controllers/element_removal_controller.js`

Tiny generic controller — useful beyond flashes (modals, dismissable banners, etc.):

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  remove() {
    this.element.remove()
  }
}
```

Lifespan is fully driven by CSS `appear-then-fade` animation. When it ends, `animationend` fires and the element removes itself.

### 5. CSS: `app/assets/stylesheets/flash.css`

Rewrite the file so the `.flashes` container is the fixed-position stacker and `.flash__item` is each pill. Add level modifiers using CSS variables (the file already uses `--flash-background` / `--flash-color`). Include `dark:` equivalents via `[data-theme="dark"]` selectors (the layout already toggles `data-theme` on `<html>` per the existing theme script at lines 13–46).

```css
@layer components {
  .flashes {
    position: fixed;
    inset-block-start: calc(var(--block-space) + var(--custom-safe-inset-top));
    inset-inline-start: 50%;
    transform: translate(-50%);
    z-index: var(--z-flash);
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    pointer-events: none;
  }

  .flash__item {
    pointer-events: auto;
    animation: appear-then-fade 3s 300ms both;
    background-color: var(--flash-background, var(--color-ink));
    color: var(--flash-color, var(--color-ink-inverted));
    border-radius: 4em;
    padding: 0.7em 1.4em;
    font-size: var(--font-size-medium);
    max-inline-size: min(90vw, 480px);
    box-shadow: 0 4px 12px rgb(0 0 0 / 0.15);
  }

  .flash__item--success { --flash-background: var(--color-success); }
  .flash__item--error   { --flash-background: var(--color-error); }
  .flash__item--warning { --flash-background: var(--color-warning); --flash-color: var(--color-ink); }
  .flash__item--info    { /* default */ }

  [data-theme="dark"] .flash__item { /* dark-mode tuning if base vars need overriding */ }
}
```

(`appear-then-fade` keyframes already exist somewhere in the CSS bundle since the current `flash.css` references them. If not, add: from `opacity: 0` → 10% `opacity: 1` → 90% `opacity: 1` → to `opacity: 0`.)

### 6. Migrate the broken callsites

**`app/views/sites/create.turbo_stream.erb`** — change the toast append to use the new partial and the `flashes` target:

```erb
<%= turbo_stream.append "flashes" do %>
  <%= render "shared/flash", message: "Adding #{@website.domain}…", level: :info %>
<% end %>
```

**`app/models/website.rb`** (around line 372–382) — `broadcast_to_subscribers` currently broadcasts a `shared/toast` to target `"toasts"`. Change to:

```ruby
Turbo::StreamsChannel.broadcast_append_later_to(
  "user_#{subscription.user_id}",
  target: "flashes",
  partial: "shared/flash",
  locals: { message: "Failed to add #{domain}: #{processing_error_message}", level: :error }
)
```

The Turbo Stream subscription `<%= turbo_stream_from "user_#{current_user.id}" %>` already exists in `app/views/sites/index.html.erb:1`. To make broadcast flashes work on every page, **move that line into the layout** under `<body>` (gated on `current_user`):

```erb
<%= turbo_stream_from "user_#{current_user.id}" if current_user %>
```

### 7. Remove the old plumbing

- Delete `app/javascript/controllers/toast_controller.js`.
- Delete `app/javascript/controllers/flash_controller.js`.
- Remove their entries from `app/javascript/controllers/index.js` (or wherever Stimulus registers controllers).
- Search for `data-controller="toast"`, `data-controller="flash"`, `window.showToast(`, `target: "toasts"`, `id="toast-container"` and remove/replace each.

## Critical files

| File | Action |
|---|---|
| `app/views/shared/_flash.html.erb` | **Create** |
| `app/views/shared/_flashes.html.erb` | **Create** |
| `app/javascript/controllers/element_removal_controller.js` | **Create** |
| `app/javascript/controllers/index.js` | Register `element-removal`; unregister `toast`, `flash` |
| `app/javascript/controllers/toast_controller.js` | **Delete** |
| `app/javascript/controllers/flash_controller.js` | **Delete** |
| `app/helpers/application_helper.rb` | Add `flash_level(type)` |
| `app/assets/stylesheets/flash.css` | Rewrite for stacking + level modifiers |
| `app/views/layouts/application.html.erb` | Replace toast block with `render "shared/flashes"`; add `turbo_stream_from` for current user |
| `app/views/sites/index.html.erb` | Remove `turbo_stream_from` (now in layout) |
| `app/views/sites/create.turbo_stream.erb` | Use `shared/flash` and target `flashes` |
| `app/models/website.rb` | Update `broadcast_to_subscribers` to use new partial / target |

## Reused utilities

- Existing `flash.css` keyframe `appear-then-fade` and CSS variables (`--flash-background`, `--flash-color`, `--z-flash`, `--block-space`, `--custom-safe-inset-top`) — reuse, don't redefine.
- `Turbo::StreamsChannel.broadcast_append_later_to` — already the project's `_later` pattern (per `STYLE.md`).
- The dark-theme switching in `application.html.erb:13-46` already sets `data-theme` on `<html>` — used for `[data-theme="dark"]` overrides.

## Verification

1. `bin/dev` → http://retrofeed.localhost:3006, log in.
2. **Server flash path**: trigger a controller that sets `flash[:notice]` / `flash[:alert]` (e.g. log out and back in). Confirm the pill appears at the top, fades after ~3.3s, and removes itself from the DOM (inspect via DevTools — should be gone, not just invisible).
3. **Turbo Stream path on same page**: from the sites index, add a new site via the modal. Confirm:
   - `Sites#create` no longer 500s.
   - An "Adding example.com…" pill appears.
   - The new site is prepended into the sidebar list (existing `Subscription#broadcast_new_site` behavior).
4. **Broadcast on a different page**: open the app on the home page, then in another tab trigger a website failure (or add a site whose processing will fail) — the failure flash should appear on the home page too, since `turbo_stream_from "user_#{id}"` is now in the layout.
5. **Stacking**: trigger two flashes in quick succession (e.g. add a site twice in 1s) — both pills should appear stacked, each fading independently.
6. **Levels**: temporarily set `flash[:error] = "test"` in a controller and reload — verify the error pill is color-coded; repeat for `:success`, `:warning`, `:info`.
7. `bin/rails test` — make sure no existing test referenced `shared/_toast`, `toast-container`, or the deleted JS controllers. Fix any that did.
8. `bin/ci` — full run (Rubocop, Brakeman, tests).
