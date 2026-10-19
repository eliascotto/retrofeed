# frozen_string_literal: true

# Renders a callout/alert box with DaisyUI styling.
#
# Supports multiple variants, optional icon, and closable state with localStorage persistence.
#
# @example Basic usage
#   <%= render CalloutComponent.new(message: "This is important information.") %>
#
# @example Info variant
#   <%= render CalloutComponent.new(message: "Tip: Use the archive page URL.", variant: :info) %>
#
# @example Closable callout with localStorage key
#   <%= render CalloutComponent.new(
#     message: "Dismiss this message",
#     closable: true,
#     storage_key: "callout_dismissed"
#   ) %>
#
class CalloutComponent < ViewComponent::Base
  VARIANTS = %i[default info success warning error].freeze
  ICONS = {
    default: "info",
    info: "info",
    success: "check",
    warning: "triangle-alert",
    error: "triangle-alert"
  }.freeze

  # @param message [String] The callout message text
  # @param variant [Symbol] Visual style (:default, :info, :success, :warning, :error)
  # @param closable [Boolean] Whether the callout can be dismissed
  # @param storage_key [String, nil] localStorage key for persisting dismissed state
  # @param show_icon [Boolean] Whether to show the variant icon
  # @param html_options [Hash] Additional HTML attributes
  def initialize(
    message:,
    variant: :default,
    closable: false,
    storage_key: nil,
    show_icon: true,
    **html_options
  )
    @message = message
    @variant = variant
    @closable = closable
    @storage_key = storage_key
    @show_icon = show_icon
    @html_options = html_options
  end

  def call
    tag.div(**wrapper_attributes) do
      safe_join([
        icon_element,
        message_element,
        close_button
      ].compact)
    end
  end

private
    def wrapper_attributes
      attrs = {
        class: wrapper_classes,
        role: "alert"
      }

      if @closable
        attrs[:data] = {
          controller: "callout",
          callout_storage_key_value: @storage_key
        }
      end

      attrs.merge(@html_options)
    end

    def wrapper_classes
      classes = [ "alert", "flex", "items-start", "gap-3" ]
      classes << variant_class
      classes.concat(Array(@html_options.delete(:class)))
      classes.compact.join(" ")
    end

    def variant_class
      case @variant
      when :default then ""
      when :info then "alert-info"
      when :success then "alert-success"
      when :warning then "alert-warning"
      when :error then "alert-error"
      end
    end

    def icon_element
      return unless @show_icon

      icon_name = ICONS[@variant] || "info"
      tag.div(class: "flex-shrink-0") do
        helpers.icon_tag(icon_name, class: "w-5 h-5")
      end
    end

    def message_element
      tag.span(@message, class: "flex-1 text-sm")
    end

    def close_button
      return unless @closable

      tag.button(
        class: "btn btn-ghost btn-xs btn-circle flex-shrink-0",
        type: "button",
        data: { action: "click->callout#dismiss" },
        "aria-label": "Dismiss"
      ) do
        helpers.icon_tag("x", class: "w-4 h-4")
      end
    end
end
