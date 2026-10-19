import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    csrfToken: String
  }

  refresh(event) {
    event.preventDefault()

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfTokenValue
      }
    }).then(response => {
      switch (response.status) {
        case 200:
          window.showFlash("Refresh started")
          setTimeout(() => window.location.reload(), 2000)
          break
        case 429:
          window.showFlash("Please wait a few minutes before refreshing again", "error")
          break
        default:
          window.showFlash("Something went wrong", "error")
      }
    })
  }
}
