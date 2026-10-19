import { Controller } from "@hotwired/stimulus"

// Controller for the confirmation modal that appears when removing a website.
// Opens a DaisyUI dialog and submits a Turbo DELETE request upon confirmation.
export default class extends Controller {
  static targets = ["websiteName"]
  static values = {
    csrfToken: String
  }

  open(websiteId, websiteName, deletePath) {
    this.websiteId = websiteId
    this.deletePath = deletePath
    this.websiteNameTarget.textContent = websiteName
    this.element.showModal()
  }

  openFromEvent(event) {
    const { id, name, path } = event.detail
    this.open(id, name, path)
  }

  close() {
    this.element.close()
  }

  confirm() {
    // Submit the delete request via Turbo
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.deletePath
    form.style.display = "none"

    // Add CSRF token
    const csrfInput = document.createElement("input")
    csrfInput.type = "hidden"
    csrfInput.name = "authenticity_token"
    csrfInput.value = this.csrfTokenValue

    // Add method override for DELETE
    const methodInput = document.createElement("input")
    methodInput.type = "hidden"
    methodInput.name = "_method"
    methodInput.value = "delete"

    form.appendChild(csrfInput)
    form.appendChild(methodInput)
    document.body.appendChild(form)

    // Close modal immediately for better UX
    this.close()

    // Submit via Turbo if available, otherwise regular submit
    if (window.Turbo) {
      form.setAttribute("data-turbo", "true")
    }
    form.submit()
  }
}
