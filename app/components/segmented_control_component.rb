# frozen_string_literal: true

# Renders a segmented control (toggle button group) with DaisyUI/Tailwind styling.
#
# A segmented control allows users to select one option from a set of mutually
# exclusive choices. The selected option is visually highlighted.
#
# @example Basic usage
#   <%= render SegmentedControlComponent.new(
#     name: "theme",
#     options: [
#       { value: "system", label: "System" },
#       { value: "light", label: "Light" },
#       { value: "dark", label: "Dark" }
#     ],
#     selected: "light"
#   ) %>
#
# @example With size
#   <%= render SegmentedControlComponent.new(
#     name: "view_mode",
#     options: [{ value: "list", label: "List" }, { value: "grid", label: "Grid" }],
#     selected: "list",
#     size: :sm
#   ) %>
#
class SegmentedControlComponent < ViewComponent::Base
  SIZES = %i[xs sm md lg].freeze

  # @param name [String] The form field name for the radio inputs
  # @param options [Array<Hash>] Array of option hashes with :value and :label keys
  # @param selected [String, nil] The currently selected value
  # @param size [Symbol] Control size (:xs, :sm, :md, :lg)
  # @param disabled [Boolean] Whether the control is disabled
  # @param full_width [Boolean] Whether the control should span full width
  # @param html_options [Hash] Additional HTML attributes for the container
  def initialize(
    name:,
    options:,
    selected: nil,
    size: :md,
    disabled: false,
    full_width: false,
    **html_options
  )
    @name = name
    @options = options
    @selected = selected || options.first&.dig(:value)
    @size = size
    @disabled = disabled
    @full_width = full_width
    @html_options = html_options
  end

  def call
    tag.div(**container_attributes) do
      safe_join(@options.map { |option| render_option(option) })
    end
  end

private
    def container_attributes
      {
        class: container_classes,
        role: "radiogroup",
        "aria-label": @name.to_s.titleize,
        **@html_options
      }
    end

    def container_classes
      classes = [
        "flex",
        "p-1",
        "rounded-xl",
        "bg-base-200",
        "dark:bg-base-200"
      ]
      classes << "w-full" if @full_width
      classes.concat(Array(@html_options.delete(:class)))
      classes.compact.join(" ")
    end

    def render_option(option)
      value = option[:value]
      label = option[:label]
      is_selected = value.to_s == @selected.to_s

      tag.label(class: label_classes) do
        safe_join([
          tag.input(
            type: "radio",
            name: @name,
            value: value,
            checked: is_selected,
            disabled: @disabled,
            class: "sr-only peer"
          ),
          tag.span(label, class: span_classes)
        ])
      end
    end

    def label_classes
      classes = [
        "select-none"
      ]
      classes << "flex-1" if @full_width
      classes << "opacity-50 cursor-not-allowed" if @disabled

      classes.compact.join(" ")
    end

    def span_classes
      classes = [
        "block",
        size_padding_class,
        "rounded-lg",
        "text-center",
        "font-medium",
        size_text_class,
        "text-base-content/70",
        "transition-all",
        "duration-200",
        "hover:bg-base-100/50",
        "dark:hover:bg-base-100/50",
        "peer-checked:bg-base-100",
        "peer-checked:dark:bg-base-100",
        "peer-checked:shadow-sm",
        "peer-checked:text-base-content"
      ]
      classes.compact.join(" ")
    end

    def size_padding_class
      case @size
      when :xs then "px-2 py-0.5"
      when :sm then "px-3 py-1"
      when :lg then "px-6 py-3"
      else "px-4 py-2"
      end
    end

    def size_text_class
      case @size
      when :xs then "text-xs"
      when :sm then "text-sm"
      when :lg then "text-lg"
      else "text-sm"
      end
    end
end
