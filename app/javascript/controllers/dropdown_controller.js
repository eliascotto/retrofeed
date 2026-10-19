import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details"]

  connect() {
    this.handleClickOutside = this.handleClickOutside.bind(this)
    this.handleToggle = this.handleToggle.bind(this)
    
    const details = this.detailsTarget || this.element.querySelector("details")
    if (details) {
      details.addEventListener("toggle", this.handleToggle)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
    const details = this.detailsTarget || this.element.querySelector("details")
    if (details) {
      details.removeEventListener("toggle", this.handleToggle)
    }
  }

  handleToggle(event) {
    const details = event.target
    if (details.hasAttribute("open")) {
      document.addEventListener("click", this.handleClickOutside)
    } else {
      document.removeEventListener("click", this.handleClickOutside)
    }
  }

  handleClickOutside(event) {
    const details = this.detailsTarget || this.element.querySelector("details")
    if (!details) return

    if (!details.contains(event.target)) {
      details.removeAttribute("open")
      document.removeEventListener("click", this.handleClickOutside)
    }
  }
}
