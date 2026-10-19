// Unified localStorage settings service for user preferences.
// Combines theme, reading, and appearance settings into a single storage key.

const STORAGE_KEY = "retrofeed_settings"

const DEFAULTS = {
  theme: "system",
  font_size: "base",
  font_family: "sans",
  content_width: "md",
  right_sidebar_collapsed: false
}

// Loads all settings from localStorage, merging with defaults.
export function loadSettings() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored) {
      return { ...DEFAULTS, ...JSON.parse(stored) }
    }
  } catch (error) {
    console.error("Error loading settings:", error)
  }
  return { ...DEFAULTS }
}

// Saves a partial settings update to localStorage.
export function saveSettings(updates) {
  try {
    const current = loadSettings()
    const merged = { ...current, ...updates }
    localStorage.setItem(STORAGE_KEY, JSON.stringify(merged))
    return merged
  } catch (error) {
    console.error("Error saving settings:", error)
    return loadSettings()
  }
}

// Gets a single setting value.
export function getSetting(key) {
  const settings = loadSettings()
  return settings[key] ?? DEFAULTS[key]
}

// Sets a single setting value.
export function setSetting(key, value) {
  return saveSettings({ [key]: value })
}

// Resolves the effective theme based on system preference.
export function getEffectiveTheme() {
  const theme = getSetting("theme")
  if (theme === "system") {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }
  return theme
}

// Applies the current theme to the document.
export function applyTheme() {
  document.documentElement.setAttribute("data-theme", getEffectiveTheme())
}

// Class mappings for reading settings.
export const FONT_SIZE_CLASSES = {
  sm: "prose-sm",
  base: "prose-base",
  lg: "prose-lg",
  xl: "prose-xl"
}

export const FONT_FAMILY_CLASSES = {
  sans: "font-sans",
  serif: "font-serif",
  mono: "font-mono"
}

export const CONTENT_WIDTH_CLASSES = {
  xs: "max-w-lg",
  sm: "max-w-xl",
  md: "max-w-2xl",
  lg: "max-w-3xl",
  xl: "max-w-4xl",
  xxl: "max-w-5xl"
}

// Ordered list of content-width steps. Index drives the stepper UI.
export const CONTENT_WIDTH_STEPS = ["xs", "sm", "md", "lg", "xl", "xxl"]
