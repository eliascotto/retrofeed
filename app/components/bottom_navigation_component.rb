# frozen_string_literal: true

# Renders a bottom navigation bar for mobile devices.
#
# Displays navigation icons horizontally fixed at the bottom of the screen.
# Only visible on mobile screens (hidden on sm and above).
#
# @example Basic usage
#   <%= render BottomNavigationComponent.new(current_user: current_user, current_path: request.path) %>
#
class BottomNavigationComponent < ViewComponent::Base
  # @param current_user [User] The currently logged in user
  # @param current_path [String] The current request path for active state detection
  def initialize(current_user:, current_path:)
    @current_user = current_user
    @current_path = current_path
  end

  # Check if the given path matches the current path
  def active?(path)
    @current_path == path
  end

  # Check if the current path starts with the given prefix
  def active_prefix?(prefix)
    @current_path.start_with?(prefix)
  end

  # CSS classes for a navigation icon based on active state
  def nav_icon_classes(active:)
    base = "flex flex-col items-center justify-center gap-0.5 py-2 px-3 rounded-lg transition-colors"
    if active
      "#{base} text-primary"
    else
      "#{base} text-base-content/50 hover:text-base-content/80"
    end
  end

  attr_reader :current_user
end
