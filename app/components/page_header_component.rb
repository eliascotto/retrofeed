# frozen_string_literal: true

# Renders a page header with back navigation, title, and optional elements.
#
# Sticky header with backdrop blur, back button with history fallback,
# title/subtitle, and optional external link.
#
# @example Basic usage
#   <%= render PageHeaderComponent.new(title: "Settings", back_path: root_path) %>
#
# @example With external link
#   <%= render PageHeaderComponent.new(
#     title: "Site Name",
#     back_path: sites_path,
#     external_link_url: "https://example.com",
#     external_link_text: "Visit"
#   ) %>
#
# @example Small size
#   <%= render PageHeaderComponent.new(title: "Sites", back_path: root_path, size: :small) %>
#
# @example Overlay variant (transparent, positioned above content)
#   <%= render PageHeaderComponent.new(variant: :overlay, back_path: root_path) %>
#
class PageHeaderComponent < ViewComponent::Base
  SIZES = %i[normal small].freeze
  VARIANTS = %i[default overlay].freeze

  # @param title [String, nil] The page title (not shown in overlay variant)
  # @param back_path [String] URL for the back button (defaults to root_path)
  # @param title_tag [Symbol] HTML tag for the title (:h1, :h2 or :p)
  # @param subtitle [String, nil] Optional subtitle text
  # @param external_link_url [String, nil] URL for external link button
  # @param external_link_text [String] Text for external link button (defaults to "Visit")
  # @param size [Symbol] Header size (:normal or :small)
  # @param favicon [String, nil] URL for the favicon
  # @param variant [Symbol] Header variant (:default or :overlay)
  # @param constrain_width [Boolean] Whether to apply inner max-width (false to fill parent container)
  def initialize(
    title: nil,
    back_path: nil,
    title_tag: :h1,
    subtitle: nil,
    external_link_url: nil,
    external_link_text: "Visit",
    size: :small,
    favicon: nil,
    favicon_use_letter_fallback: false,
    variant: :default,
    constrain_width: true
  )
    @title = title
    @back_path = back_path
    @title_tag = title_tag
    @subtitle = subtitle
    @external_link_url = external_link_url
    @external_link_text = external_link_text
    @size = size
    @favicon = favicon
    @favicon_use_letter_fallback = favicon_use_letter_fallback
    @variant = variant
    @constrain_width = constrain_width
  end

  def overlay?
    @variant == :overlay
  end

private
    def back_fallback_path
      @back_path || helpers.root_path
    end

    def header_height_class
      @size == :small ? "h-12" : "h-16"
    end

    def header_classes
      base = "top-0 z-10 #{header_height_class} flex items-center"

      if overlay?
        "#{base} absolute bg-transparent"
      else
        "#{base} sticky bg-base-100/95 backdrop-blur border-b border-base-200 dark:bg-base-100/95 dark:border-base-200"
      end
    end

    def inner_wrapper_classes
      if @constrain_width
        "mx-auto px-3 w-full"
      else
        "w-full"
      end
    end

    def back_button_classes
      base = [ "btn", "btn-sm", "btn-circle", "shrink-0", "text-base",
        "text-base-content/50", "hover:text-base-content" ]

      if overlay?
        base << "bg-base-100/60"
      else
        base << "btn-ghost"
      end

      base.join(" ")
    end
end
