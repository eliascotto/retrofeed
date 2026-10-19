import { Controller } from "@hotwired/stimulus"
import { getSetting, setSetting, applyTheme } from "services/user_settings"

// Controls theme settings on the appearances settings page.
// Uses the unified user_settings service for localStorage persistence.
export default class extends Controller {
  static targets = ["control"]

  connect() {
    this.loadTheme()
  }

  loadTheme() {
    const savedTheme = getSetting("theme")
    this.selectRadio(savedTheme)
    applyTheme()
  }

  setTheme(event) {
    const theme = event.target.value
    setSetting("theme", theme)
    applyTheme()
  }

  selectRadio(value) {
    if (!this.hasControlTarget) return

    const radio = this.controlTarget.querySelector(`input[value="${value}"]`)
    if (radio) {
      radio.checked = true
    }
  }
}
