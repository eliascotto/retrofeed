class WebProcessor
  # Service for cleaning article titles by removing common suffixes
  module TitleCleaner
    extend self

    # Common delimiters used to separate title from site name
    DELIMITERS = [
      " — ",  # em-dash with spaces
      " - ",  # hyphen with spaces
      " | ",  # pipe with spaces
      " – ",  # en-dash with spaces
      " —",   # em-dash with leading space only
      " -",   # hyphen with leading space only
      " |",   # pipe with leading space only
      " –"    # en-dash with leading space only
    ].freeze

    DELIMITED_REGEX = / [—\-|–] ?/

    # Minimum percentage of titles that must share a suffix for it to be considered common
    MIN_SUFFIX_THRESHOLD = 0.6

    # Cleans a title by removing the website's title suffix pattern,
    # useful for archive articles.
    #
    # @param title [String] The title to clean
    # @param website [Website] The website to use for suffix pattern
    # @return [String] The cleaned title
    def clean_archive_title(title, website)
      return nil if title.blank?
      return title if website.title_suffix_pattern.blank?

      clean_using_suffix(title, website.title_suffix_pattern)
    end

    # Removes the suffix pattern from a title if present
    #
    # @param title [String, nil] The title to clean
    # @param page_title [String, nil] The html page title
    # @param article [Article, nil] The original article
    # @param website [Website, nil] The website the article belongs to
    # @return [String, nil] The cleaned title, or nil if title was nil
    def clean_article_title(title, article)
      cleaned = title.present? ? title.dup : article.title
      website = article.website

      # If second part is the website name, return only the title
      if (parts = cleaned.split(DELIMITED_REGEX, 2)).length > 1
        return parts.first if parts.last.include?(website.name)
      end

      clean_using_suffix(cleaned, website.title_suffix_pattern)
    end

    # Detects a common suffix pattern across multiple titles
    #
    # Analyzes titles to find a suffix that appears in the majority of them.
    # This helps identify site-specific suffixes like " — overreacted" or " | Site Name"
    #
    # @param titles [Array<String>] Array of title strings to analyze
    # @return [String, nil] The most common suffix pattern, or nil if none found
    def detect_common_suffix(titles)
      return nil if titles.blank? || titles.length < 3

      # Filter out nil/blank titles
      valid_titles = titles.compact.reject(&:blank?)
      return nil if valid_titles.length < 3

      # Try each delimiter
      DELIMITERS.each do |delimiter|
        suffix_counts = count_suffixes(valid_titles, delimiter)
        next if suffix_counts.empty?

        # Find the most common suffix
        most_common_suffix, count = suffix_counts.max_by { |_, c| c }
        next unless most_common_suffix

        # Check if it meets the threshold
        percentage = count.to_f / valid_titles.length
        if percentage >= MIN_SUFFIX_THRESHOLD
          return most_common_suffix
        end
      end

      nil
    end

    private
      def clean_using_suffix(title, suffix)
        cleaned = title.dup
        # Remove the suffix pattern if it appears at the end
        if suffix.present? && cleaned.end_with?(suffix)
          cleaned = cleaned[0...-suffix.length].strip
        end
        cleaned
      end

      # Counts how many titles end with each suffix for a given delimiter
      #
      # @param titles [Array<String>] Array of title strings
      # @param delimiter [String] The delimiter to split on
      # @return [Hash<String, Integer>] Hash mapping suffix to count
      def count_suffixes(titles, delimiter)
        suffix_counts = Hash.new(0)
        # Ensure delimiter is UTF-8 encoded
        delimiter_utf8 = delimiter.dup.force_encoding(Encoding::UTF_8)

        titles.each do |title|
          # Ensure title is UTF-8 encoded
          title_utf8 = title.dup.force_encoding(Encoding::UTF_8)
          # Only consider titles that contain the delimiter
          next unless title_utf8.include?(delimiter_utf8)

          # Split on delimiter and get the last part (suffix)
          parts = title_utf8.split(delimiter_utf8, -1)
          next if parts.length < 2

          suffix = delimiter_utf8 + parts.last.strip
          # Only count if suffix is at the end of the title
          if title_utf8.end_with?(suffix)
            suffix_counts[suffix] += 1
          end
        end

        suffix_counts
      end
  end
end
