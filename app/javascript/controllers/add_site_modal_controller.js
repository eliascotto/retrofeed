import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["urlInput"]

  open() {
    this.element.showModal()
    requestAnimationFrame(() => this.urlInputTarget?.focus())
  }

  close() {
    this.element.close()
  }

  onSubmitEnd(event) {
    if (event.detail.success) {
      this.close()
    }
  }
}

