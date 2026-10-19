import { Controller } from "@hotwired/stimulus"

// Controller for the Create/Edit Reading List modal. The form itself is a
// Turbo-driven form_with, so this controller is only responsible for UI
// concerns: opening/closing the dialog, previewing the cover image,
// title-based submit enabling, and closing on a successful Turbo submit.
//
// A single edit modal is shared across all reading lists: when an "Edit"
// trigger fires `openEditList`, the event detail carries the target list's
// form action, title, description, and cover URL, which we use to populate the
// form before opening.
export default class extends Controller {
  static targets = [
    "form",
    "titleInput",
    "titleError",
    "submitBtn",
    "coverPreview",
    "coverPlaceholder",
    "coverImage",
    "coverInput",
    "descriptionInput"
  ]
  static values = {
    editMode: { type: Boolean, default: false }
  }

  openCreateFromEvent() {
    if (!this.editModeValue) this.open()
  }

  openEditFromEvent(event) {
    if (this.editModeValue) {
      this.populate(event.detail)
      this.open()
    }
  }

  // Fills the shared edit form from the clicked trigger's data params.
  populate({ url, title, description, cover }) {
    this.formTarget.action = url
    this.titleInputTarget.value = title || ""
    this.descriptionInputTarget.value = description || ""
    this.setCover(cover)
    this.validateForm()
  }

  setCover(coverUrl) {
    if (this.hasCoverImageTarget && this.hasCoverPlaceholderTarget) {
      this.coverInputTarget.value = ""
      if (coverUrl) {
        this.coverImageTarget.src = coverUrl
        this.coverImageTarget.classList.remove("hidden")
        this.coverPlaceholderTarget.classList.add("hidden")
      } else {
        this.coverImageTarget.removeAttribute("src")
        this.coverImageTarget.classList.add("hidden")
        this.coverPlaceholderTarget.classList.remove("hidden")
      }
    }
  }

  open() {
    this.element.showModal()
    setTimeout(() => this.titleInputTarget.focus(), 0)
  }

  close() {
    this.element.close()
  }

  validateForm() {
    this.submitBtnTarget.disabled = !this.titleInputTarget.value.trim()
  }

  triggerCoverUpload(event) {
    event.preventDefault()
    if (this.hasCoverInputTarget) this.coverInputTarget.click()
  }

  previewCover(event) {
    const file = event.target.files[0]
    if (!file) return
    if (!file.type.startsWith("image/")) return
    if (file.size > 5 * 1024 * 1024) return

    const reader = new FileReader()
    reader.onload = (e) => {
      if (this.hasCoverImageTarget && this.hasCoverPlaceholderTarget) {
        this.coverImageTarget.src = e.target.result
        this.coverImageTarget.classList.remove("hidden")
        this.coverPlaceholderTarget.classList.add("hidden")
      }
    }
    reader.readAsDataURL(file)
  }

  // Fires after Turbo finishes the form submission. event.detail.success is
  // true for any 2xx/3xx response — the controller redirects on both success
  // and validation failure, so we close the dialog and let the followed
  // redirect render any flash.
  submitEnd(event) {
    if (event.detail.success) this.close()
  }
}
