# ADR: Turbo Prefetch and Article View Tracking

## Status

Accepted

## Context

Retrofeed tracks when users view articles by creating or updating `ReadingState`
records. This allows the app to show reading history and mark articles as read.

Hotwire Turbo prefetches pages when users hover over links, improving perceived
performance by having the page ready when they click. However, this creates a
problem for view tracking:

1. **Prefetch phase (hover)**: Turbo sends a real HTTP GET request to fetch the
   article page HTML and caches it. The request includes a `Purpose: prefetch`
   header (or `Sec-Purpose: prefetch`).

2. **Click phase**: When the user clicks, Turbo serves the cached HTML response.
   No new HTTP request is made to the server.

If we track views in the Rails `show` action:
- Tracking on all requests would incorrectly record views for hovered articles
- Skipping prefetch requests (via header check) means no tracking happens at all,
  because the click uses the cached response without a new request

## Decision

Move view tracking from the server-side `show` action to a client-side Stimulus
controller that fires when the article page actually renders in the browser.

### Implementation

1. **New API endpoint**: `POST /api/articles/:id/track_view`
   - Creates or touches a `ReadingState` record for the current user
   - Located in `Api::ArticlesController#track_view`

2. **Stimulus controller**: `article_view_controller.js`
   - Attached to the article show page container
   - Calls `track_view` endpoint in its `connect()` callback
   - Fire-and-forget: no response handling needed for analytics

3. **View integration**: `articles/show.html.erb`
   - Container div gets `data-controller="article-view"` and URL value

4. **Show action cleanup**: `ArticlesController#show`
   - No longer handles `ReadingState` creation
   - Comment explains why and references this ADR

### Why This Works

Turbo prefetch only fetches and caches HTML. It does not:
- Execute JavaScript
- Mount Stimulus controllers
- Trigger `connect()` callbacks

These only happen when the page is actually rendered in the browser after the
user clicks. By moving tracking to Stimulus `connect()`, we accurately track
real views while allowing prefetch to improve performance.

## Consequences

### Positive

- Accurate view tracking: only records when user actually views an article
- Prefetch continues to work, maintaining fast navigation
- Clear separation: server renders content, client tracks engagement
- Works with browser back/forward navigation (Stimulus reconnects)

### Negative

- Requires JavaScript: views won't be tracked if JS is disabled
- Slight delay: tracking happens after page render, not on request
- Additional HTTP request per view (minimal overhead)

### Neutral

- Pattern can be reused for other engagement tracking (time on page, scroll depth)

## Files Changed

- `config/routes.rb` - Added `track_view` route
- `app/controllers/api/articles_controller.rb` - Added `track_view` action
- `app/javascript/controllers/article_view_controller.js` - New controller
- `app/views/articles/show.html.erb` - Attached controller to container
- `app/controllers/articles_controller.rb` - Removed inline tracking

## Alternatives Considered

### 1. Disable prefetch for article links

Add `data-turbo-prefetch="false"` to article links in `ArticleItem::Component`.

**Rejected because**: Loses the performance benefit of prefetching. Users would
notice slower navigation.

### 2. Track in show action with prefetch detection + separate click endpoint

Keep tracking in show action for non-prefetch requests, add separate endpoint
for when prefetch was used.

**Rejected because**: Complex coordination needed between server and client to
know when prefetch was used. Stimulus-only approach is simpler and more reliable.

### 3. Use Turbo event listeners instead of Stimulus

Listen to `turbo:load` globally and track based on URL.

**Rejected because**: Less targeted than a controller on the specific element.
Stimulus approach is more idiomatic for Hotwire apps and easier to maintain.

## References

- [Turbo Prefetch Documentation](https://turbo.hotwired.dev/handbook/drive#prefetching-links-on-hover)
- [Stimulus Lifecycle Callbacks](https://stimulus.hotwired.dev/reference/lifecycle-callbacks)
