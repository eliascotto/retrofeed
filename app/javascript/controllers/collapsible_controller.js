import { Controller } from "@hotwired/stimulus"
import { getSetting, setSetting } from "services/user_settings"

export default class extends Controller {
  static targets = ["panel", "iconClose", "iconOpen"]
  static values = { key: String }   // e.g. data-collapsible-key-value="menu_collapsed"

  connect() {
    const collapsed = getSetting(this.keyValue)
    this.apply(collapsed)
  }

  toggle() {
    const collapsed = !getSetting(this.keyValue)
    setSetting(this.keyValue, collapsed)
    this.apply(collapsed)
  }

  apply(collapsed) {
    this.element.classList.toggle("is-collapsed", collapsed)
    this.iconCloseTarget.classList.toggle("hidden", collapsed)
    this.iconOpenTarget.classList.toggle("hidden", !collapsed)
  }
}