# frozen_string_literal: true

# Renders an input field with DaisyUI styling.
#
# Supports multiple types, variants, sizes, and states.
#
# @example Basic usage
#   <%= render InputComponent.new(name: "email", placeholder: "Enter email") %>
#
# @example With variant and size
#   <%= render InputComponent.new(name: "search", variant: :bordered, size: :sm) %>
#
# @example Number input with min/max
#   <%= render InputComponent.new(type: :number, name: "page", value: 1, min: 1, max: 10, size: :xs) %>
#
# @example URL input
#   <%= render InputComponent.new(type: :url, name: "website", placeholder: "https://example.com", required: true) %>
#
class InputComponent < ViewComponent::Base
  TYPES = %i[text email password url number tel search date datetime_local time].freeze
  VARIANTS = %i[default bordered ghost].freeze
  SIZES = %i[xs sm md lg].freeze

  # @param type [Symbol] Input type (:text, :email, :password, :url, :number, :tel, :search, :date, :datetime_local, :time)
  # @param name [String] Input name attribute
  # @param value [String, nil] Input value
  # @param placeholder [String, nil] Placeholder text
  # @param variant [Symbol] Visual style (:default, :bordered, :ghost)
  # @param size [Symbol] Input size (:xs, :sm, :md, :lg)
  # @param disabled [Boolean] Whether the input is disabled
  # @param required [Boolean] Whether the input is required
  # @param readonly [Boolean] Whether the input is readonly
  # @param autofocus [Boolean] Whether the input should be autofocused
  # @param autocomplete [String, nil] Autocomplete attribute value
  # @param min [Integer, nil] Minimum value (for number inputs)
  # @param max [Integer, nil] Maximum value (for number inputs)
  # @param step [Integer, nil] Step value (for number inputs)
  # @param minlength [Integer, nil] Minimum length
  # @param maxlength [Integer, nil] Maximum length
  # @param pattern [String, nil] Validation pattern
  # @param html_options [Hash] Additional HTML attributes
  def initialize(
    id: nil,
    type: :text,
    name: nil,
    value: nil,
    placeholder: nil,
    variant: :default,
    size: :md,
    disabled: false,
    required: false,
    readonly: false,
    autofocus: false,
    autocomplete: nil,
    min: nil,
    max: nil,
    step: nil,
    minlength: nil,
    maxlength: nil,
    pattern: nil,
    **html_options
  )
    @id = id
    @type = type
    @name = name
    @value = value
    @placeholder = placeholder
    @variant = variant
    @size = size
    @disabled = disabled
    @required = required
    @readonly = readonly
    @autofocus = autofocus
    @autocomplete = autocomplete
    @min = min
    @max = max
    @step = step
    @minlength = minlength
    @maxlength = maxlength
    @pattern = pattern
    @html_options = html_options
  end

  def call
    tag.input(**input_attributes)
  end

private
    def input_attributes
      attrs = {
        id: @id,
        type: input_type,
        name: @name,
        value: @value,
        placeholder: @placeholder,
        disabled: @disabled || nil,
        required: @required || nil,
        readonly: @readonly || nil,
        autofocus: @autofocus || nil,
        autocomplete: @autocomplete,
        min: @min,
        max: @max,
        step: @step,
        minlength: @minlength,
        maxlength: @maxlength,
        pattern: @pattern,
        class: input_classes
      }.compact

      attrs.merge(@html_options)
    end

    def input_type
      # Convert datetime_local to datetime-local for HTML
      @type == :datetime_local ? "datetime-local" : @type.to_s
    end

    def input_classes
      classes = [ "input" ]
      classes << variant_class
      classes << size_class
      classes.concat(Array(@html_options.delete(:class)))
      classes.compact.join(" ")
    end

    def variant_class
      case @variant
      when :bordered then "input-bordered"
      when :ghost then "input-ghost"
      else nil
      end
    end

    def size_class
      case @size
      when :xs then "input-xs"
      when :sm then "input-sm"
      when :lg then "input-lg"
      else nil
      end
    end
end
