module ApplicationHelper
  # Highlight search terms in text with case-insensitive matching
  def highlight_search(text, query)
    return text if query.blank? || text.blank?

    # Convert to string if needed
    text_str = text.to_s
    query_str = query.to_s

    # Escape HTML in text first
    escaped_text = ERB::Util.html_escape(text_str)

    # Create regex pattern for case-insensitive matching
    # Escape special regex characters in query
    escaped_query = Regexp.escape(query_str)
    pattern = Regexp.new(escaped_query, Regexp::IGNORECASE)

    # Replace matches with highlighted version
    escaped_text.gsub(pattern) do |match|
      "<mark class='bg-primary/20 text-primary'>#{match}</mark>"
    end.html_safe
  end

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  # Convert level to standard format
  def flash_level(type)
    case type.to_sym
    when :notice, :success then :success
    when :alert, :error    then :error
    when :warning          then :warning
    else                        :info
    end
  end

  def flash_icon(level)
    case level
    when :success then "circle-check"
    when :error, :warning then "circle-alert"
    else nil
    end
  end
end
