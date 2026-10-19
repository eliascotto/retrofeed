# frozen_string_literal: true

# Renders a dropdown menu using DaisyUI's native dropdown component.
#
# Uses a hybrid approach: CSS focus method for desktop, Popover API for mobile.
# This prevents off-screen positioning issues on small screens (< 380px).
#
# @example Basic usage with block content
#   <%= render DropdownComponent.new do |dropdown| %>
#     <% dropdown.with_item(label: "Edit", icon: "square-pen") %>
#     <% dropdown.with_item(label: "Delete", icon: "trash") %>
#   <% end %>
#
# @example With custom trigger
#   <%= render DropdownComponent.new(trigger_icon: "settings", trigger_class: "btn-primary") do |dropdown| %>
#     <% dropdown.with_item(label: "Settings", icon: "settings") %>
#   <% end %>
#
# @example With custom positioning
#   <%= render DropdownComponent.new(position: "bottom-right") do |dropdown| %>
#     <% dropdown.with_item(label: "Profile", icon: "user") %>
#   <% end %>
#
#   <%= render DropdownComponent.new(position: "top") do |dropdown| %>
#     <% dropdown.with_item(label: "Options", icon: "settings") %>
#   <% end %>
#
class DropdownComponent < ViewComponent::Base
  renders_one :trigger
  renders_many :items, "DropdownComponent::ItemComponent"

  # @param trigger_icon [String] Icon name for the trigger button (default: ellipsis)
  # @param trigger_label [String, nil] Optional label for the trigger button
  # @param trigger_class [String] Additional CSS classes for the trigger button
  # @param position [String] Position of the dropdown menu (default: bottom-left)
  #   Valid values: bottom-left, bottom-right, bottom, top-left, top-right, top, left, right
  # @param use_popover_on_mobile [Boolean] Whether to use Popover API on mobile (default: true)
  # @param html_options [Hash] Additional HTML attributes for the wrapper
  def initialize(
    trigger_icon: "ellipsis",
    trigger_label: nil,
    trigger_class: "",
    position: "bottom-left",
    size: "md",
    use_popover_on_mobile: true,
    **html_options
  )
    @trigger_icon = trigger_icon
    @trigger_label = trigger_label
    @trigger_class = trigger_class
    @position = position
    @size = size
    @use_popover_on_mobile = use_popover_on_mobile
    @html_options = html_options

    # Generate unique IDs for popover API
    @unique_id = SecureRandom.hex(4)
  end

  def popover_id
    "popover-#{@unique_id}"
  end

  def anchor_name
    "--anchor-#{@unique_id}"
  end

  def dropdown_classes
    classes = [ "dropdown" ]

    # Map position to DaisyUI classes
    case @position
    when "bottom-right", "right"
      classes << "dropdown-end"
    when "top-left", "top"
      classes << "dropdown-top"
    when "top-right"
      classes << "dropdown-top dropdown-end"
    when "left"
      classes << "dropdown-left"
    when "bottom-left"
      classes << "dropdown-end"
    end

    classes << @html_options[:class] if @html_options[:class].present?
    classes.join(" ")
  end

  # When a custom trigger slot is provided, the caller is responsible for
  # styling the trigger content. The wrapper button only carries the optional
  # @trigger_class so it can stretch full-width, become circular, etc.
  def trigger_classes
    if trigger?
      @trigger_class.presence || ""
    else
      [
        "btn btn-ghost btn-xs px-1 shadow-none",
        "text-base-content/40 hover:text-base-content",
        @trigger_class
      ].compact.reject(&:blank?).join(" ")
    end
  end

  def menu_classes
    classes = [
      "dropdown-content menu bg-base-100 dark:bg-base-100 rounded-box z-[100] p-1 shadow-xl border border-base-200 text-base-content"
    ]

    case @size
    when "md" then classes << "min-w-52"
    when "sm" then classes << "min-w-40"
    when "lg" then classes << "min-w-64"
    end

    classes.join(" ")
  end

  def popover_menu_classes
    classes = [
      "dropdown menu bg-base-100 dark:bg-base-100 rounded-box z-[100] p-1 shadow-xl border border-base-200 text-base-content"
    ]

    case @size
    when "md" then classes << "min-w-52"
    when "sm" then classes << "min-w-40"
    when "lg" then classes << "min-w-64"
    end

    classes.join(" ")
  end

  # CSS anchor positioning style for popover menu
  # Uses position-area (formerly inset-area) to position the popover relative to the anchor
  # On mobile, we always align the right edge of the menu to the anchor to prevent overflow
  def popover_style
    position_area = case @position
    when "top", "top-left", "top-right"
      "top span-left"
    else
      # Default to bottom, aligned so the right edge of the menu aligns with right edge of anchor
      "bottom span-left"
    end

    # position-area is the new name (Chrome 125+), inset-area is the old name
    # Adding both for maximum browser compatibility
    "position-anchor: #{anchor_name}; position-area: #{position_area}; inset-area: #{position_area}"
  end
end
