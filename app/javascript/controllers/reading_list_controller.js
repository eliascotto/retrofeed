import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    listId: Number,
    articleId: Number,
  }

  addToReadNext(event) {
    event.preventDefault()
    event.stopPropagation()

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const articleId = event.currentTarget.dataset.articleIdValue

    if (!articleId) {
      console.error('Missing articleId', { articleId })
      return
    }

    fetch(`/api/lists/read-next/articles`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ article_id: articleId })
    })
    .then(response => {
      if (response.ok) {
        // Hide the "Read Next" option after adding
        this.element.closest("li")?.remove()

        window.showFlash("Article added to Read Next")

        // Close the dropdown
        document.activeElement.blur()
      }
    })
  }

  removeArticle(event) {
    event.preventDefault()
    event.stopPropagation()

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Read values from the clicked element
    const listId = event.currentTarget.dataset.listIdValue
    const articleId = event.currentTarget.dataset.articleIdValue

    if (!listId || !articleId) {
      console.error('Missing listId or articleId', { listId, articleId })
      return
    }

    fetch(`/api/lists/${listId}/articles/${articleId}`, {
      method: "DELETE",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
    })
    .then(response => {
      if (response.ok) {
        // Close the dropdown
        document.activeElement.blur()

        // Reload the page
        window.location.reload()
      }
    })
  }
}
