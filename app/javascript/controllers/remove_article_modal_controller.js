import { Controller } from "@hotwired/stimulus"

// Controller for the confirmation modal that appears when removing an article from the library.
// Opens a dialog and submits a Turbo POST request upon confirmation.
export default class extends Controller {
  static values = { csrfToken: String }

  open(removePath) {
    this.removePath = removePath
    this.element.showModal()
  }

  openFromEvent(event) {
    const { path } = event.detail
    this.open(path)
  }

  close() {
    this.element.close()
  }

  confirm() {
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.removePath
    form.style.display = "none"

    const csrfInput = document.createElement("input")
    csrfInput.type = "hidden"
    csrfInput.name = "authenticity_token"
    csrfInput.value = this.csrfTokenValue

    form.appendChild(csrfInput)
    document.body.appendChild(form)

    this.close()

    if (window.Turbo) {
      form.setAttribute("data-turbo", "true")
    }
    form.submit()
  }
}
