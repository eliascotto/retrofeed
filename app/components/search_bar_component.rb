# frozen_string_literal: true

# Renders a search bar with optional clear button and stimulus controller support.
#
# The component renders a form with a search input, search icon, and optional
# clear button. It supports different sizes and can be integrated with Stimulus
# controllers.
#
# @example Basic usage
#   <%= render SearchBarComponent.new(action_url: search_path) %>
#
# @example With value and placeholder
#   <%= render SearchBarComponent.new(
#     action_url: search_path,
#     value: @query,
#     placeholder: "Search articles..."
#   ) %>
#
# @example With clear button and stimulus controller
#   <%= render SearchBarComponent.new(
#     action_url: search_path,
#     value: @query,
#     show_clear_button: true,
#     data_controller: "search",
#     data_action: "submit->search#handleSubmit"
#   ) %>
#
class SearchBarComponent < ViewComponent::Base
  SIZES = %i[sm md lg].freeze
  SHORTCUT_KEY = "⌘K".freeze

  # @param action_url [String] The URL to submit the search form to
  # @param value [String, nil] Current search value
  # @param placeholder [String] Placeholder text for the input
  # @param size [Symbol] Input size (:sm, :md, :lg)
  # @param show_clear_button [Boolean] Whether to show clear button when value is present
  # @param autofocus [Boolean] Whether to autofocus the input
  # @param data_controller [String, nil] Stimulus controller name for the form
  # @param data_action [String, nil] Stimulus action for form submit
  # @param data_form_target [String, nil] Stimulus target for the form
  # @param data_input_target [String, nil] Stimulus target for the input
  # @param data_clear_action [String, nil] Stimulus action for clear button
  # @param hidden_fields [Hash] Additional hidden fields to include in the form.
  #   Simple format: { name: value }
  #   With data attributes: { name: { value: value, data: { target: "controller#target" } } }
  def initialize(
    action_url:,
    value: nil,
    placeholder: "Search...",
    size: :md,
    autofocus: false,
    data_controller: nil,
    data_action: nil,
    data_form_target: nil,
    data_input_target: nil,
    data_clear_action: nil,
    show_clear_button: false,
    show_shortcut_tag: false,  # Default combination for search is ⌘K
    hidden_fields: {}
  )
    @action_url = action_url
    @value = value
    @placeholder = placeholder
    @size = size
    @show_clear_button = show_clear_button
    @show_shortcut_tag = show_shortcut_tag
    @autofocus = autofocus
    @data_controller = data_controller
    @data_action = data_action
    @data_form_target = data_form_target
    @data_input_target = data_input_target
    @data_clear_action = data_clear_action
    @hidden_fields = hidden_fields
  end

private
    def form_attributes
      attrs = { action: @action_url, method: "get" }
      attrs["data-controller"] = @data_controller if @data_controller
      attrs["data-action"] = @data_action if @data_action
      attrs["data-#{@data_controller}-target"] = @data_form_target if @data_controller && @data_form_target
      attrs
    end

    def input_classes
      base_classes = "w-full shadow-none outline-none focus:border-primary
        bg-base-200"
      padding_classes = padding_class
      shortcut_tag_classes = @show_shortcut_tag ? "pr-2" : ""
      "#{base_classes} #{padding_classes} #{shortcut_tag_classes}"
    end

    def padding_class
      # Padding for search icon on left and clear button on right
      if @show_clear_button
        case @size
        when :sm then "pl-8 pr-8"
        when :lg then "pl-12 pr-12"
        else "pl-9 pr-10"
        end
      else
        case @size
        when :sm then "pl-8"
        when :lg then "pl-12"
        else "pl-9"
        end
      end
    end

    def icon_size_class
      case @size
      when :sm then "w-3.5 h-3.5"
      when :lg then "w-5 h-5"
      else "w-4 h-4"
      end
    end

    def icon_left_position
      case @size
      when :sm then "left-2"
      when :lg then "left-4"
      else "left-3"
      end
    end

    def icon_right_position
      case @size
      when :sm then "right-2"
      when :lg then "right-4"
      else "right-2"
      end
    end

    def clear_button_size
      case @size
      when :sm then "w-6 h-6"
      when :lg then "w-10 h-10"
      else "w-8 h-8"
      end
    end

    def input_data_attributes
      attrs = {}
      attrs["data-#{@data_controller}-target"] = @data_input_target if @data_controller && @data_input_target
      attrs
    end

    def clear_button_action
      @data_clear_action || (@data_controller ? "click->#{@data_controller}#clear" : nil)
    end

    def show_clear_button?
      @show_clear_button && @value.present?
    end

    def hidden_field_data_attrs(config)
      return {} unless config[:data]

      config[:data].transform_keys { |key| "data-#{key}" }
    end
end
