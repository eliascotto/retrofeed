import { Controller } from "@hotwired/stimulus"

// Tracks article views by calling the track_view API endpoint when the
// controller connects to the DOM.
//
// Why this exists:
// Turbo prefetches pages on hover, which triggers real HTTP requests to the
// server. If we tracked views in the Rails show action, we'd incorrectly
// record views for articles the user only hovered over. When the user
// actually clicks, Turbo serves the cached prefetched response, so no new
// request is made.
//
// How it works:
// This Stimulus controller only connects when the page is actually rendered
// in the browser (after a click), not during prefetch. The connect() callback
// fires and sends a POST to /api/articles/:id/track_view to record the view.
//
// See: docs/adr_turbo_prefetch_view_tracking.md
export default class extends Controller {
  static values = {
    articleId: Number,
    url: String
  }

  connect() {
    this.trackView()
  }

  trackView() {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Fire-and-forget: we don't need to handle the response for tracking
    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      }
    })
  }
}
