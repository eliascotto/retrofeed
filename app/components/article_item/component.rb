# frozen_string_literal: true

# Renders a single article item in a list.
#
# Displays the article title, metadata (publication date, word count, website),
# and a context menu dropdown with actions like copy link and add to list.
#
# @example Basic usage
#   <%= render ArticleItem::Component.new(article: @article) %>
#
# @example With read state
#   <%= render ArticleItem::Component.new(article: @article, is_read: true, read_at: 1.day.ago) %>
#
# @example In a list context
#   <%= render ArticleItem::Component.new(article: @article, list: @list, in_read_next: true) %>
#
class ArticleItem::Component < ViewComponent::Base
  include TimeHelper

  attr_reader :current_user, :article,
    :is_read,
    :is_new,
    :read_at,
    :in_read_next,
    :show_website,
    :show_favicon,
    :show_word_count,
    :list

  # @param article [Article] The article to display
  # @param is_read [Boolean] Whether the article has been read
  # @param read_at [Time, nil] When the article was read
  # @param in_read_next [Boolean] Whether the article is in the Read Next list
  # @param show_website [Boolean] Whether to show the website name
  # @param list [List, nil] The list context (for remove from list action)
  def initialize(
    current_user:,
    article:,
    is_read: false,
    is_new: false,
    read_at: nil,
    in_read_next: false,
    show_website: false,
    show_favicon: false,
    show_word_count: false,
    list: nil
  )
    @current_user = current_user
    @article = article
    @is_read = is_read
    @is_new = is_new
    @read_at = read_at
    @in_read_next = in_read_next
    @show_website = show_website
    @show_favicon = show_favicon
    @show_word_count = show_word_count
    @list = list
  end

  # Article title with fallback
  def title
    @article.title.presence || "Untitled"
  end

  # Formatted publication date
  def formatted_date
    @article.publication_date&.strftime("%b %d, %Y")
  end

  # Website display name
  def website_name
    @article.website.name.presence || @article.website.domain
  end

  # Check if we should show word count
  def show_word_count?
    @show_word_count && @article.word_count && @article.word_count > 0
  end

  # Formatted word count
  def formatted_word_count
    helpers.number_with_delimiter(@article.word_count)
  end

  # Whether to show the separator before publication date
  def show_date_separator?
    @show_website && @article.website && @article.publication_date
  end

  # Whether to show the separator before word count
  def show_word_count_separator?
    @article.publication_date || (@show_website && @article.website)
  end

  # Whether to show the separator before read at
  def show_read_at_separator?
    @article.publication_date || show_word_count? || (@show_website && @article.website)
  end

  # Formatted "read at" time
  def read_at_text
    "Read #{short_time_ago_in_words(@read_at)} ago" if @read_at
  end

  def user_has_article?
    @current_user.has_article?(@article)
  end

  def user_has_article_removed?
    user_article = UserArticle.find_by(user: current_user, article: @article)
    user_article.present? && user_article.removed_at
  end

  # Returns the list of dropdown menu items for the article context menu.
  # Each item is a hash of options passed to DropdownComponent#with_item.
  def dropdown_items
    items = []

    if @article.status == "failed"
      items << {
        label: "Retry download",
        icon: "cloud-download",
        href: "#",
        data: {
          controller: "download-article",
          action: "click->download-article#download",
          download_article_article_id_value: @article.id
        }
      }
    end

    items << {
      label: "Copy link",
      icon: "clipboard",
      data: {
        controller: "clipboard",
        action: "click->clipboard#copy",
        clipboard_text_value: @article.url
      }
    }

    if @is_read
      items << {
        label: "Mark as unread",
        icon: "x",
        href: "#",
        data: {
          controller: "user-article",
          action: "click->user-article#markUnread",
          user_article_article_id_value: @article.id
        }
      }
    else
      items << {
        label: "Mark as read",
        icon: "check",
        href: "#",
        data: {
          controller: "user-article",
          user_article_article_id_value: @article.id,
          action: "click->user-article#markRead"
        }
      }
    end

    if user_has_article_removed?
      items << {
        label: "Restore",
        icon: "undo",
        href: "#",
        data: {
          controller: "restore-article",
          action: "click->restore-article#restore",
          restore_article_path_value: helpers.restore_user_article_path(article_id: @article.id)
        }
      }
    else
      items << {
        label: "Remove from library",
        icon: "trash",
        href: "#",
        data: {
          controller: "modal-trigger",
          action: "click->modal-trigger#open",
          modal_trigger_event_value: "openRemoveArticle",
          modal_trigger_path_param: helpers.remove_user_article_path(article_id: @article.id)
        }
      }
    end

    items << { hr: true }

    unless @in_read_next
      items << {
        label: "Add to Read Next",
        icon: "bookmark",
        href: "#",
        data: {
          controller: "reading-list",
          article_id_value: @article.id,
          action: "click->reading-list#addToReadNext"
        }
      }
    end

    items << {
      label: "Add to list",
      icon: "list",
      href: "#",
      data: {
        controller: "modal-trigger",
        action: "click->modal-trigger#open",
        modal_trigger_event_value: "openAddToList",
        modal_trigger_article_id_param: @article.id,
      }
    }

    if @list.present?
      items << {
        label: "Remove from list",
        icon: "list-x",
        href: "#",
        data: {
          controller: "reading-list",
          list_id_value: @list.id,
          article_id_value: @article.id,
          action: "click->reading-list#removeArticle"
        }
      }
    end

    items
  end

  def status_icon
    return nil unless user_has_article? && !article.has_content?
    case @article.status
    when "crawling", "extracting" then "cloud-download"
    when "failed"                 then "cloud-alert"
    end # completed → nil
  end

  def status_tooltip
    "Failed to fetch content. Try again later." if article.status == "failed"
  end

  def title_color_class
    article.has_content? ? "text-base-content" : "text-base-content/50"
  end

  CLICKABLE_CLASSES = "flex-1 flex flex-row items-center gap-2 min-w-0"
  NON_CLICKABLE_CLASSES = "flex-1 flex flex-row items-center gap-2 min-w-0 cursor-default"

  private
    def article_item_container
      # When article has content go to article page,
      # when article doesn't have content, download it and add it to user's articles
      if user_has_article?
        if @article.has_content?
          link_to helpers.article_path(@article), class: CLICKABLE_CLASSES do
            yield
          end
        else # Do nothing since article doesn't have content
          content_tag :div, class: NON_CLICKABLE_CLASSES do
            yield
          end
        end
      else # user doesn't have article
        content_tag :div,
          data: {
            controller: "download-article",
            action: "click->download-article#download",
            download_article_article_id_value: @article.id
          },
          class: CLICKABLE_CLASSES do
            yield
          end
      end
    end
end
