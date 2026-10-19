# frozen_string_literal: true

# Renders the main navigation sidebar.
#
# Displays the app logo, navigation links, add site button, and user menu.
# Highlights the active navigation item based on the current path.
# Supports responsive icon-only mode on medium screens.
#
# @example Basic usage
#   <%= render SidebarComponent.new(current_user: current_user, current_path: request.path) %>
#
class SidebarComponent < ViewComponent::Base
  # Navigation item structure for the main nav links
  NavItem = Struct.new(:path, :icon, :label, :active_check, keyword_init: true)

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
  # Responsive: icon-only on sm/md, full on lg
  def nav_link_classes(active:)
    base = "flex items-center gap-2 py-2 rounded text-sm transition-colors cursor-default"
    responsive = "justify-center lg:justify-start px-1.5 lg:px-2"
    if active
      "#{base} #{responsive} text-base-content bg-base-200 font-medium"
    else
      "#{base} #{responsive} text-base-content/60 hover:bg-base-200"
    end
  end

  # Get the read next list for the current user
  def read_next_list
    @current_user.read_next_list
  end

  # Check if in development environment
  def development?
    Rails.env.development?
  end

  attr_reader :current_user
end
