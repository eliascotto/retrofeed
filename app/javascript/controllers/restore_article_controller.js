import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { path: String }

  connect() { }

  restore() {
    fetch(this.pathValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    }).then(response => {
      switch (response.status) {
        case 404:
          window.showFlash("Article not found", "error")
          break
        default:
          window.showFlash("Something went wrong", "error")
      }
    })
  }
}
