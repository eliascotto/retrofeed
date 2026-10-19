import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  copy(event) {
    event.preventDefault()
    event.stopPropagation()

    navigator.clipboard.writeText(this.textValue).then(() => {
      document.activeElement.blur()
    })
  }
}
