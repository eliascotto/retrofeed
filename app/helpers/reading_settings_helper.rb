module ReadingSettingsHelper
  FONT_SIZES = [
    { value: "sm",   label: "A", label_class: "text-xs" },
    { value: "base", label: "A", label_class: "text-sm" },
    { value: "lg",   label: "A", label_class: "text-base" },
    { value: "xl",   label: "A", label_class: "text-lg" }
  ].freeze

  FONT_FAMILIES = [
    { value: "sans",  label: "Sans",  btn_class: "font-sans" },
    { value: "serif", label: "Serif", btn_class: "font-serif" },
    { value: "mono",  label: "Mono",  btn_class: "font-mono" }
  ].freeze

  THEMES = [
    { value: "system", label: "Auto" },
    { value: "light",  label: "Light" },
    { value: "dark",   label: "Dark" }
  ].freeze

  # Toggle-style groups only. content_width is rendered separately as a stepper.
  READING_SETTING_GROUPS = [
    { key: :font_size,   title: "Text Size", options: FONT_SIZES,    action: "setFontSize" },
    { key: :font_family, title: "Font",      options: FONT_FAMILIES, action: "setFontFamily" },
    { key: :theme,       title: "Theme",     options: THEMES,        action: "setTheme" }
  ].freeze

  # Checkout user_settings.js for CONTENT_WIDTH_STEPS

  def reading_setting_groups
    READING_SETTING_GROUPS
  end

  def reading_setting_target(group_key, value)
    "#{group_key.to_s.camelize(:lower)}#{value.to_s.camelize}"
  end
end
