import { Controller } from "@hotwired/stimulus"

// Controls the mobile drawer menu.
// Handles opening and closing the drawer via checkbox toggle.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    // Expose global function to open the drawer from anywhere
    window.openMobileDrawer = () => this.open()
  }

  disconnect() {
    delete window.openMobileDrawer
  }

  open() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = true
    }
  }

  close() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = false
    }
  }

  toggle() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = !this.toggleTarget.checked
    }
  }
}

