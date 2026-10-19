# frozen_string_literal: true

# Renders a mobile drawer menu using DaisyUI's drawer component.
#
# The drawer slides in from the left and contains the full sidebar navigation.
# It is controlled by a Stimulus controller and is only visible on mobile.
#
# @example Basic usage
#   <%= render DrawerComponent.new(current_user: current_user, current_path: request.path) %>
#
class DrawerComponent < ViewComponent::Base
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

  # CSS classes for a navigation link based on active state
  def nav_link_classes(active:)
    base = "flex items-center gap-3 px-4 py-3 rounded-lg text-base transition-colors"
    if active
      "#{base} text-base-content bg-base-200 font-medium"
    else
      "#{base} text-base-content/70 hover:bg-base-200"
    end
  end

  # Get the read next list for the current user
  def read_next_list
    @current_user.read_next_list
  end

  attr_reader :current_user
end
