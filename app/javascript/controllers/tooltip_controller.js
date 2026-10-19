import { Controller } from "@hotwired/stimulus"
import { computePosition, flip, shift, offset } from "@floating-ui/dom"

export default class extends Controller {
  static targets = ["tooltip", "anchor"]
  static values = { placement: String, delay: Number }

  connect() {
    this._mouseEnter = this.mouseEnter.bind(this)
    this._mouseOut = this.mouseOut.bind(this)

    requestAnimationFrame(() => {
      this.element.addEventListener("mouseenter", this._mouseEnter)
      this.element.addEventListener("mouseleave", this._mouseOut)
    })
  }


  disconnect() {
    this.element.removeEventListener("mouseenter", this._mouseEnter)
    this.element.removeEventListener("mouseleave", this._mouseOut)
  }

  mouseEnter(retryCount = 0) {
    const anchor = this.hasAnchorTarget ? this.anchorTarget : this.element
    const anchorRect = anchor.getBoundingClientRect()

    // Anchor exists but hasn't stabilized (still full container width)
    if (this.hasAnchorTarget && anchorRect.width > 100 && retryCount < 10) {
      requestAnimationFrame(() => this.mouseEnter(retryCount + 1))
      return
    }

    // Set position: fixed before display: block to prevent the tooltip from
    // briefly entering normal flow and shifting layout, which would corrupt
    // the anchor measurement used by computePosition on first render.
    Object.assign(this.tooltipTarget.style, {
      position: "fixed",
      left: "0",
      top: "0",
      visibility: "hidden",
      display: "block",
    })

    this.#position().then(() => {
      if (this.delayValue) {
        setTimeout(() => {
          this.tooltipTarget.style.visibility = "visible"
        }, this.delayValue)
      } else {
        this.tooltipTarget.style.visibility = "visible"
      }
    })
  }

  mouseOut() {
    this.tooltipTarget.style.display = "none"
  }

  #position() {
    const anchor = this.hasAnchorTarget ? this.anchorTarget : this.element
    return computePosition(anchor, this.tooltipTarget, {
      placement: this.placementValue || "top",
      middleware: [offset(6), flip(), shift({ padding: 8 })],
    }).then(({ x, y }) => {
      this.tooltipTarget.style.left = `${x}px`
      this.tooltipTarget.style.top = `${y}px`
    })
  }
}
