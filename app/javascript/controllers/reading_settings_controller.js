import { Controller } from "@hotwired/stimulus"
import {
  loadSettings,
  setSetting,
  applyTheme,
  FONT_SIZE_CLASSES,
  FONT_FAMILY_CLASSES,
  CONTENT_WIDTH_CLASSES,
  CONTENT_WIDTH_STEPS
} from "services/user_settings"

// Controls reading settings dropdown and applies settings to the article view.
// Settings are persisted in localStorage via the unified user_settings service.
export default class extends Controller {
  static targets = [
    "fontSizeSm", "fontSizeBase", "fontSizeLg", "fontSizeXl",
    "fontFamilySans", "fontFamilySerif", "fontFamilyMono",
    "contentWidthSmaller", "contentWidthLarger",
    "themeSystem", "themeLight", "themeDark",
    "content", "article"
  ]

  connect() {
    this.fontSizeClasses = FONT_SIZE_CLASSES
    this.fontFamilyClasses = FONT_FAMILY_CLASSES
    this.contentWidthClasses = CONTENT_WIDTH_CLASSES
    this.contentWidthSteps = CONTENT_WIDTH_STEPS
    this.loadAndApplySettings()
  }

  loadAndApplySettings() {
    const settings = loadSettings()

    // Update button states to reflect current settings
    this.updateButtonStates("fontSize", settings.font_size)
    this.updateButtonStates("fontFamily", settings.font_family)
    this.updateButtonStates("theme", settings.theme)

    // Content width uses a two-button stepper, not toggle buttons
    const currentWidth = this.normalizeWidth(settings.content_width)
    this.updateWidthStepperState(currentWidth)

    // Apply settings to the article
    this.applyFontSize(settings.font_size)
    this.applyFontFamily(settings.font_family)
    this.applyContentWidth(currentWidth)
    applyTheme()
  }

  setFontSize(event) {
    const value = event.params.value
    this.updateButtonStates("fontSize", value)
    this.applyFontSize(value)
    setSetting("font_size", value)
  }

  setFontFamily(event) {
    const value = event.params.value
    this.updateButtonStates("fontFamily", value)
    this.applyFontFamily(value)
    setSetting("font_family", value)
  }

  // Step the content width one notch narrower, clamped to the first step.
  widthSmaller() {
    this.stepContentWidth(-1)
  }

  // Step the content width one notch wider, clamped to the last step.
  widthLarger() {
    this.stepContentWidth(+1)
  }

  setTheme(event) {
    const value = event.params.value
    this.updateButtonStates("theme", value)
    setSetting("theme", value)
    applyTheme()
  }

  updateButtonStates(group, activeValue) {
    const targetMap = {
      fontSize: ["fontSizeSm", "fontSizeBase", "fontSizeLg", "fontSizeXl"],
      fontFamily: ["fontFamilySans", "fontFamilySerif", "fontFamilyMono"],
      theme: ["themeSystem", "themeLight", "themeDark"]
    }

    const valueMap = {
      fontSize: { sm: "fontSizeSm", base: "fontSizeBase", lg: "fontSizeLg", xl: "fontSizeXl" },
      fontFamily: { sans: "fontFamilySans", serif: "fontFamilySerif", mono: "fontFamilyMono" },
      theme: { system: "themeSystem", light: "themeLight", dark: "themeDark" }
    }

    targetMap[group].forEach(targetName => {
      const target = this[`${targetName}Target`]
      if (target) {
        target.classList.remove("btn-soft")
        target.classList.add("btn-ghost")
      }
    })

    const activeTarget = this[`${valueMap[group][activeValue]}Target`]
    if (activeTarget) {
      activeTarget.classList.remove("btn-ghost")
      activeTarget.classList.add("btn-soft")
    }
  }

  applyFontSize(value) {
    const content = this.findContentElement()
    if (!content) return

    Object.values(this.fontSizeClasses).forEach(cls => {
      content.classList.remove(cls)
    })
    content.classList.add(this.fontSizeClasses[value])
  }

  applyFontFamily(value) {
    const content = this.findContentElement()
    if (!content) return

    Object.values(this.fontFamilyClasses).forEach(cls => {
      content.classList.remove(cls)
    })
    content.classList.add(this.fontFamilyClasses[value])
  }

  applyContentWidth(value) {
    const article = this.findArticleElement()
    if (!article) return

    const safeValue = this.normalizeWidth(value)
    Object.values(this.contentWidthClasses).forEach(cls => {
      article.classList.remove(cls)
    })
    article.classList.add(this.contentWidthClasses[safeValue])
  }

  findContentElement() {
    if (this.hasContentTarget) {
      return this.contentTarget
    }
    return document.querySelector("[data-reading-settings-target='content']")
  }

  findArticleElement() {
    if (this.hasArticleTarget) {
      return this.articleTarget
    }
    return document.querySelector("[data-reading-settings-target='article']")
  }

  // Returns a value guaranteed to be in CONTENT_WIDTH_STEPS. Falls back to the
  // middle step (md) when stale localStorage values like narrow/default/wide
  // are encountered after the xs..xl rename.
  normalizeWidth(value) {
    if (this.contentWidthSteps.includes(value)) {
      return value
    } else {
      return "md"
    }
  }

  // Walks the ordered width scale by `delta` steps, clamped to [0, last].
  // Updates UI, persists, and applies the new width.
  stepContentWidth(delta) {
    const current = this.normalizeWidth(loadSettings().content_width)
    const currentIndex = this.contentWidthSteps.indexOf(current)
    const lastIndex = this.contentWidthSteps.length - 1
    const nextIndex = Math.max(0, Math.min(lastIndex, currentIndex + delta))

    if (nextIndex === currentIndex) {
      return
    }

    const nextValue = this.contentWidthSteps[nextIndex]
    this.applyContentWidth(nextValue)
    this.updateWidthStepperState(nextValue)
    setSetting("content_width", nextValue)
  }

  // Toggles disabled state on the stepper buttons at the edges of the scale.
  updateWidthStepperState(value) {
    const index = this.contentWidthSteps.indexOf(value)
    const lastIndex = this.contentWidthSteps.length - 1

    if (this.hasContentWidthSmallerTarget) {
      this.setStepperDisabled(this.contentWidthSmallerTarget, index <= 0)
    }
    if (this.hasContentWidthLargerTarget) {
      this.setStepperDisabled(this.contentWidthLargerTarget, index >= lastIndex)
    }
  }

  setStepperDisabled(button, disabled) {
    if (disabled) {
      button.setAttribute("disabled", "disabled")
      button.classList.add("btn-disabled")
    } else {
      button.removeAttribute("disabled")
      button.classList.remove("btn-disabled")
    }
  }
}
