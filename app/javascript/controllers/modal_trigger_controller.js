import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { event: { type: String, default: "openAddWebsite" } }

  open(e) {
    e.preventDefault()
    e.stopPropagation()

    this.dispatch(this.eventValue, {
      target: window,
      prefix: "modal",
      detail: e.params,
    })
  }
}
