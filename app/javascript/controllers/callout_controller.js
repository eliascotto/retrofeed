import { Controller } from "@hotwired/stimulus"

// Handles dismissable callouts with optional localStorage persistence.
// When a storage key is provided, the dismissed state persists across page loads.
export default class extends Controller {
  static values = {
    storageKey: String
  }

  connect() {
    if (this.shouldHide()) {
      this.element.remove()
    }
  }

  dismiss() {
    if (this.hasStorageKeyValue && this.storageKeyValue) {
      localStorage.setItem(this.storageKeyValue, "true")
    }
    this.element.remove()
  }

  shouldHide() {
    if (!this.hasStorageKeyValue || !this.storageKeyValue) {
      return false
    }
    return localStorage.getItem(this.storageKeyValue) === "true"
  }
}
