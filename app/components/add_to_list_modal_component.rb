# frozen_string_literal: true

# Modal component for adding an article to a reading list.
#
# Displays a searchable list of user's reading lists with keyboard navigation.
# Supports creating new lists on the fly when no matches exist.
#
# @example Basic usage
#   <%= render AddToListModalComponent.new(lists: current_user.reading_lists) %>
#
class AddToListModalComponent < ViewComponent::Base
  # @param lists [ActiveRecord::Relation] The user's reading lists
  def initialize(lists:)
    @lists = lists
  end

  attr_reader :lists

  # Returns lists data as JSON for the Stimulus controller
  def lists_json
    lists.map do |list|
      {
        id: list.id,
        title: list.title
      }
    end.to_json
  end
end
