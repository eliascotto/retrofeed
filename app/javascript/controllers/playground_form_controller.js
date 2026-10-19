import { Controller } from "@hotwired/stimulus"

// Controller to toggle between pagination and infinite scroll options
export default class extends Controller {
  static targets = [
    "infiniteScrollCheckbox",
    "paginationCheckbox",
    "maxPagesInput",
    "maxScrollsInput"
  ]

  connect() {
    this.updateOptions()
  }

  toggleInfiniteScroll() {
    if (this.infiniteScrollCheckboxTarget.checked) {
      this.paginationCheckboxTarget.checked = false
    }
    this.updateOptions()
  }

  togglePagination() {
    if (this.paginationCheckboxTarget.checked) {
      this.infiniteScrollCheckboxTarget.checked = false
    }
    this.updateOptions()
  }

  updateOptions() {
    const useInfiniteScroll = this.infiniteScrollCheckboxTarget.checked

    // Disable pagination options when infinite scroll is enabled
    this.maxPagesInputTarget.disabled = useInfiniteScroll

    // Enable max scrolls only when infinite scroll is enabled
    this.maxScrollsInputTarget.disabled = !useInfiniteScroll

    // Uncheck pagination if infinite scroll is checked
    if (useInfiniteScroll) {
      this.paginationCheckboxTarget.checked = false
    }
  }
}
