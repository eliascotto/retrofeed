import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { fallback: String }

  navigate(e) {
    if (window.history.length > 1)
      window.history.back()
    else
      window.location.href = this.fallbackValue
  }
}
