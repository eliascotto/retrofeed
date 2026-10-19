# frozen_string_literal: true

# Inner component for dropdown menu items
#
# @example Basic item
#   <% dropdown.with_item(label: "Edit", icon: "square-pen") %>
#
# @example Item with link
#   <% dropdown.with_item(label: "View", href: "/view") %>
#
# @example Disabled item
#   <% dropdown.with_item(label: "Disabled", disabled: true) %>
#
class DropdownComponent::ItemComponent < ViewComponent::Base
  # @param label [String] The menu item text
  # @param icon [String, nil] Icon name to display
  # @param icon_left [Boolean] If true, icon appears on left side of label (default: false, icon on right)
  # @param description [String, nil] Description text on the right
  # @param href [String, nil] Link URL (renders as anchor if provided)
  # @param disabled [Boolean] Whether the item is disabled
  # @param hr [Boolean] Whether to render a horizontal rule
  # @param data [Hash] Data attributes for the element
  # @param html_options [Hash] Additional HTML attributes
  def initialize(
    label: nil,
    icon: nil,
    icon_left: false,
    description: nil,
    href: nil,
    disabled: false,
    hr: false,
    data: {},
    **html_options
  )
    @label = label
    @icon = icon
    @icon_left = icon_left
    @description = description
    @href = href
    @disabled = disabled
    @hr = hr
    @data = data
    @html_options = html_options
  end

  def render_icon
    return "".html_safe unless @icon.present?

    helpers.icon_tag(@icon, class: "w-4 h-4 opacity-60")
  end

  def merged_data_attributes
    @data.merge({ dropdown_action: true })
  end

  def item_classes
    classes = [ "flex items-center w-full text-sm cursor-default" ]
    classes << "opacity-40 cursor-not-allowed" if @disabled
    classes.join(" ")
  end

  def item_content_classes
    base = "flex items-center w-full"
    if @icon_left
      "#{base} gap-2"
    else
      "#{base} justify-between gap-4"
    end
  end
end
