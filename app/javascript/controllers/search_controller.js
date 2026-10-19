import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "tabInput", "form"]

  connect() {
    this.timeout = null

    // Position the cursor at the end of the input field
    const len = this.inputTarget.value.length
    this.inputTarget.focus()
    this.inputTarget.setSelectionRange(len, len)
  }

  handleSubmit(_) {
    // If user explicitly submits (Enter key), cancel any pending debounce and submit immediately
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
    // Let the form submit normally (Turbo will handle it)
  }

  switchTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.tabInputTarget.value = tab
    this.submitForm()
  }

  clear() {
    this.inputTarget.value = ""
    this.inputTarget.focus()
    this.submitForm()
  }

  submitForm() {
    // Submit the form via Turbo
    this.formTarget.requestSubmit()
  }
}
