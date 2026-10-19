# Guards against pagination traps and detects end-of-archive conditions
#
# This class implements multiple safety mechanisms to prevent the scraper from
# falling into AI traps, bot honeypots, and infinite pagination loops. It tracks
# visited URLs, content fingerprints, and discovered post URLs to detect:
#
# 1. **Circular pagination traps**: Same URLs appearing multiple times
# 2. **Content fingerprint traps**: Identical page content on different URLs
# 3. **Page number jump traps**: Sudden jumps (e.g., page 5 → page 999999)
# 4. **Empty page traps**: Consecutive pages with no content
# 5. **Duplicate post traps**: Pages that only contain posts we've already seen
#
# These checks help avoid:
# - Infinite loops that waste resources
# - Bot traps designed to waste scraper time
# - Honeypot pages that generate infinite content
# - AI detection systems that create fake pagination
#
# Usage:
#   guard = PaginationGuard.new
#   while guard.safe_to_continue?(page_url: url, page_number: num, content_fingerprint: fp, discovered_posts: posts)
#     # process page
#   end
#   guard.halt_reason  # => :circular_url, :empty_pages, etc.
#
class PaginationGuard
  # Content similarity threshold for fingerprint matching
  # Used to detect duplicate content across different URLs (bot trap indicator)
  CONTENT_SIMILARITY_THRESHOLD = 0.95

  attr_reader :halt_reason, :halt_subreason

  def initialize(
    max_page_jump: Website::PAGINATION_MAX_PAGE_JUMP,
    max_consecutive_empty: Website::PAGINATION_MAX_CONSECUTIVE_EMPTY,
    max_duplicate_streak: Website::PAGINATION_MAX_DUPLICATE_STREAK
  )
    @max_page_jump = max_page_jump
    @max_consecutive_empty = max_consecutive_empty
    @max_duplicate_streak = max_duplicate_streak

    @seen_urls = Set.new
    @content_fingerprints = Set.new
    @post_urls = Set.new
    @last_page_number = 0
    @consecutive_empty = 0
    @duplicate_post_streak = 0
    @halt_reason = nil
    @halt_subreason = nil
  end

  # Checks if it's safe to continue pagination
  #
  # Performs multiple safety checks to detect traps and prevent infinite loops:
  #
  # 1. **URL revisit check**: Detects if we've already visited this exact URL
  #    (prevents circular pagination loops)
  #
  # 2. **Page number jump check**: Detects sudden jumps in page numbers
  #    (e.g., page 5 → page 999999) which often indicates bot traps
  #
  # 3. **Content fingerprint check**: Detects duplicate content on different URLs
  #    (prevents honeypot pages that serve the same content with different URLs)
  #
  # 4. **Empty page check**: Detects consecutive pages with no posts
  #    (indicates we've reached the end or hit a trap)
  #
  # 5. **Duplicate post check**: Detects pages that only contain posts we've
  #    already seen (prevents circular pagination where posts repeat)
  #
  # @param page_url [String] The URL of the current page being processed
  # @param page_number [Integer, nil] The page number if parseable from URL
  # @param content_fingerprint [String] Hash of page content for duplicate detection
  # @param discovered_posts [Array<String>] Post URLs discovered on this page
  # @return [Boolean] true if safe to continue, false if should halt
  def safe_to_continue?(page_url:, page_number: nil, content_fingerprint:, discovered_posts:)
    return false if halted?

    # Check for URL revisit (circular pagination trap)
    # This prevents infinite loops where pagination links cycle back to earlier pages
    if @seen_urls.include?(page_url)
      halt!(:circular_url, "Already visited: #{page_url}")
      return false
    end
    @seen_urls << page_url

    # Check for page number jump (bot trap indicator)
    # Sudden jumps (e.g., page 5 → page 999999) often indicate AI traps designed
    # to waste scraper resources by generating fake high-numbered pages
    if page_number && @last_page_number > 0
      jump = page_number - @last_page_number
      if jump > @max_page_jump
        halt!(:page_jump, "Jump from #{@last_page_number} to #{page_number} exceeds max #{@max_page_jump}")
        return false
      end
      @last_page_number = page_number
    elsif page_number
      @last_page_number = page_number
    end

    # Check for duplicate content fingerprint (honeypot detection)
    # Same content on different URLs indicates a trap that serves identical
    # pages with different URLs to waste scraper time
    if @content_fingerprints.include?(content_fingerprint)
      halt!(:duplicate_content, "Content fingerprint already seen")
      return false
    end
    @content_fingerprints << content_fingerprint

    # Check for empty pages (end-of-content detection)
    # Consecutive empty pages usually mean we've reached the end of the archive
    # or hit a trap that serves empty pages
    if discovered_posts.empty?
      @consecutive_empty += 1
      if @consecutive_empty >= @max_consecutive_empty
        halt!(:empty_pages, "#{@consecutive_empty} consecutive empty pages")
        return false
      end
    else
      @consecutive_empty = 0
    end

    # Check for duplicate posts (circular pagination detection)
    # Pages that only contain posts we've already seen indicate pagination
    # has looped back or we're in a trap that repeats the same posts
    new_posts = discovered_posts.reject { |url| @post_urls.include?(url) }
    if new_posts.empty? && discovered_posts.any?
      @duplicate_post_streak += 1
      if @duplicate_post_streak >= @max_duplicate_streak
        halt!(:circular_pagination, "#{@duplicate_post_streak} pages with only duplicate posts")
        return false
      end
    else
      @duplicate_post_streak = 0
      discovered_posts.each { |url| @post_urls << url }
    end

    true
  end

  # Whether pagination has been halted
  #
  # @return [Boolean]
  def halted?
    @halt_reason.present?
  end

  # Total unique posts discovered so far
  #
  # @return [Integer]
  def total_posts_discovered
    @post_urls.size
  end

  # Total pages visited so far
  #
  # @return [Integer]
  def total_pages_visited
    @seen_urls.size
  end

  # Generates a content fingerprint from page URL and discovered post URLs
  #
  # This fingerprint is used to detect duplicate content across different URLs,
  # which is a common bot trap pattern. Instead of hashing the full HTML (which
  # can vary due to ads, timestamps, etc.), we hash the structural content:
  # the page URL and the list of post URLs found on that page.
  #
  # This approach is more stable and reliable for detecting honeypot pages that
  # serve the same content with different URLs to waste scraper resources.
  #
  # @param page_url [String] The page URL
  # @param post_urls [Array<String>] URLs of posts discovered on the page
  # @return [String] SHA256 fingerprint
  def self.generate_fingerprint(page_url, post_urls)
    content = [ page_url, *post_urls.sort ].join("\n")
    Digest::SHA256.hexdigest(content)
  end

  private

  # Marks pagination as halted with a reason
  #
  # @param reason [Symbol] The halt reason
  # @param subreason [String, nil] Additional context
  def halt!(reason, subreason = nil)
    @halt_reason = reason
    @halt_subreason = subreason
    Rails.logger.info("[PaginationGuard] Halted: #{reason} - #{subreason}")
  end
end
