import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-gray-200", "dark:bg-gray-800", "font-medium"]

export default class extends Controller {
  static targets = ["link"]

  select(event) {
    this.linkTargets.forEach((el) => el.classList.remove(...ACTIVE_CLASSES))
    event.currentTarget.classList.add(...ACTIVE_CLASSES)
  }
}
