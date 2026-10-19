import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { articleId: Number }

  markRead(event)   { this.#post(event, "mark_read") }
  markUnread(event) { this.#delete(event, "mark_read") }

  #post(event, path) {
    event.preventDefault(); event.stopPropagation(); this.#fire(event, path, "POST")
  }

  #delete(event, path) {
    event.preventDefault(); event.stopPropagation(); this.#fire(event, path, "DELETE")
  }

  #fire(event, path, method) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const articleId = event.currentTarget.dataset.userArticleArticleIdValue
    if (!articleId) { console.error("Missing articleId"); return }

    fetch(`/user_articles/${articleId}/${path}`, {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken }
    }).then(response => {
      if (response.ok) {
        document.activeElement.blur()
        Turbo.cache.clear() // Invalidate cache, helpful for state variations like read/unread
        window.location.reload()
      }
    })
  }
}
