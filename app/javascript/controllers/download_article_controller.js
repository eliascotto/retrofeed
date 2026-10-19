import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { articleId: String }
  
  connect() { }
  
  download() {
    fetch(`/articles/${this.articleIdValue}/download`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    }).then(response => {
      if (response.ok) {
        console.log("Download started for article", this.articleIdValue)
        return
      }

      switch (response.status) {
      case 404:
        window.showFlash("Article not found", "error")
        break
      case 403:
        window.showFlash("You don't have permission to download this article", "error")
        break
      default:
        window.showFlash("Something went wrong", "error")
      }
    })
  }
}

