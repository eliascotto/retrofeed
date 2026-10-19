# Parses and enforces robots.txt rules for respectful web scraping
#
# This service fetches robots.txt files, parses them according to RFC 9309,
# caches parsed rules per domain, and provides methods to check if paths are
# allowed and to enforce crawl delays.
#
# Key features:
# - Fetches robots.txt from domain root before scraping
# - Caches parsed rules per domain (24-hour TTL)
# - Respects User-agent specific rules (falls back to "*")
# - Enforces path matching with longest-match-wins logic
# - Handles Allow/Disallow rules (Allow overrides Disallow for equal specificity)
# - Enforces crawl-delay between requests
# - Fails open (allows scraping) if robots.txt is missing or inaccessible
#
# Usage:
#   robots = RobotsTxt.fetch_for("https://example.com/page")
#   if robots&.allowed?("/archive")
#     # Fetch archive
#   end
#   RobotsTxt.enforce_crawl_delay_for("https://example.com/page")
#
class RobotsTxt
  # Default user agent string for robots.txt requests
  # Can be overridden via RETROFEED_USER_AGENT environment variable
  DEFAULT_USER_AGENT = ENV.fetch("RETROFEED_USER_AGENT", "retrofeed").freeze

  # Default crawl delay in seconds when not specified in robots.txt
  DEFAULT_CRAWL_DELAY = 1.0

  # Random jitter to add to crawl delays to avoid predictable patterns
  # This makes the scraper's request timing less predictable and more human-like,
  # helping to avoid detection by anti-bot systems that look for regular intervals.
  # Jitter is added as a percentage of the base delay (0.0 to 0.3 = 0% to 30%).
  CRAWL_DELAY_JITTER_RANGE = 0.0..0.3

  # Cache TTL for robots.txt entries (24 hours)
  CACHE_TTL = 24.hours

  # Internal struct representing a single Allow or Disallow rule
  # @!attribute [r] type
  #   @return [:allow, :disallow] The rule type
  # @!attribute [r] path
  #   @return [String] The path pattern to match
  Rule = Struct.new(:type, :path)

  class << self
    # Fetches and caches a RobotsTxt instance for the given URL's domain
    #
    # Returns a cached instance if available and not expired, otherwise fetches
    # and parses robots.txt from the domain root.
    #
    # @param url [String] Any URL from the domain (e.g., "https://example.com/page")
    # @param refresh [Boolean] If true, bypass cache and fetch fresh robots.txt
    # @return [RobotsTxt, nil] Parsed robots.txt instance, or nil if fetch fails
    #
    # @example
    #   robots = RobotsTxt.fetch_for("https://example.com/archive")
    #   robots.allowed?("/archive") # => true or false
    def fetch_for(url, refresh: false)
      uri = Addressable::URI.parse(UrlUtils.validate_and_normalize_url(url))
      key = cache_key(uri)

      # Return cached instance if available and not expired
      cached = cache[key]
      if !refresh && cached && !expired?(cached[:fetched_at])
        return cached[:robots]
      end

      # Fetch and cache new instance
      robots = new(uri)
      cache[key] = { robots: robots, fetched_at: Time.current }
      robots
    rescue UrlUtils::InvalidUrlError, Addressable::URI::InvalidURIError => e
      Rails.logger.warn("[RobotsTxt] Invalid URL for robots fetch (#{url}): #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.warn("[RobotsTxt] Failed to fetch robots.txt for #{url}: #{e.message}")
      # Return cached instance if available, even if expired
      cached ? cached[:robots] : nil
    end

    # Clears the in-memory cache of robots.txt instances and request timestamps
    #
    # Useful for testing or forcing fresh fetches.
    def clear_cache!
      @cache = {}
      @last_request_times = {}
    end

    # Returns the default user agent string used for robots.txt requests
    #
    # @return [String] The user agent string (default: "retrofeed")
    def default_user_agent
      DEFAULT_USER_AGENT
    end

    # Enforces crawl delay for a URL by fetching robots.txt and sleeping if needed
    #
    # This is a convenience method that combines fetch_for and enforce_crawl_delay_with.
    #
    # @param url [String] The URL to enforce delay for
    # @param user_agent [String] The user agent to check crawl-delay for
    # @return [void]
    def enforce_crawl_delay_for(url, user_agent: default_user_agent)
      robots = fetch_for(url)
      enforce_crawl_delay_with(robots, url, user_agent: user_agent)
    end

    # Enforces crawl delay by sleeping if necessary before making a request
    #
    # Tracks the last request time per domain and sleeps if the elapsed time
    # since the last request is less than the required crawl-delay.
    #
    # Adds random jitter to the delay to avoid predictable request patterns that
    # could be detected by anti-bot systems. The jitter is a random percentage
    # (0-30%) of the base delay, making timing less regular and more human-like.
    #
    # This helps avoid AI traps and bot detection systems that monitor for:
    # - Exact timing intervals (e.g., exactly 1.0s between requests)
    # - Perfectly regular request patterns
    # - Non-human behavior patterns
    #
    # @param robots [RobotsTxt, nil] The robots.txt instance (can be nil)
    # @param url [String] The URL being requested
    # @param user_agent [String] The user agent to check crawl-delay for
    # @return [void]
    def enforce_crawl_delay_with(robots, url, user_agent: default_user_agent)
      base_delay = robots&.crawl_delay(user_agent) || DEFAULT_CRAWL_DELAY
      return if base_delay.nil? || base_delay <= 0

      # Add random jitter to avoid predictable patterns
      # Jitter is a random percentage (0-30%) of the base delay
      jitter_multiplier = 1.0 + rand(CRAWL_DELAY_JITTER_RANGE)
      delay = base_delay * jitter_multiplier

      uri = Addressable::URI.parse(UrlUtils.validate_and_normalize_url(url))
      key = cache_key(uri)
      now = Time.current
      last = last_request_times[key]

      # Sleep if not enough time has passed since last request
      if last
        elapsed = now - last
        if elapsed < delay
          sleep_time = delay - elapsed
          Rails.logger.info("[RobotsTxt] Respecting crawl-delay #{base_delay}s (+#{((jitter_multiplier - 1.0) * 100).round(1)}% jitter) for #{key}, sleeping #{sleep_time.round(2)}s")
          sleep(sleep_time)
        end
      end

      # Update last request time for this domain
      last_request_times[key] = Time.current
    rescue StandardError => e
      Rails.logger.warn("[RobotsTxt] Failed to enforce crawl delay for #{url}: #{e.message}")
    end

    private

    # Returns the in-memory cache hash of robots.txt instances
    #
    # @return [Hash] Hash keyed by domain, values are { robots: RobotsTxt, fetched_at: Time }
    def cache
      @cache ||= {}
    end

    # Returns the hash tracking last request time per domain
    #
    # Used to enforce crawl-delay by tracking when we last made a request to each domain.
    #
    # @return [Hash] Hash keyed by domain, values are Time objects
    def last_request_times
      @last_request_times ||= {}
    end

    # Generates a cache key from a URI (scheme://host:port)
    #
    # @param uri [Addressable::URI] The URI to generate a key for
    # @return [String] Cache key string
    def cache_key(uri)
      "#{uri.scheme}://#{uri.host}#{uri.port ? ":#{uri.port}" : ""}"
    end

    # Checks if a cached robots.txt entry has expired
    #
    # @param fetched_at [Time, nil] When the entry was fetched
    # @return [Boolean] true if expired or missing timestamp
    def expired?(fetched_at)
      return true unless fetched_at
      Time.current - fetched_at > CACHE_TTL
    end
  end

  # Initializes a new RobotsTxt instance and fetches/parses robots.txt
  #
  # @param uri [Addressable::URI] The URI for the domain to fetch robots.txt from
  def initialize(uri)
    @uri = uri
    # Hash of user agents -> { rules: [], crawl_delay: nil }
    @rules_by_agent = Hash.new { |h, k| h[k] = { rules: [], crawl_delay: nil } }
    robots_body = fetch_and_parse
    parse(robots_body) if robots_body.present?
  end

  # Checks if a path is allowed according to robots.txt rules
  #
  # Rules are matched using longest-prefix matching. If multiple rules match,
  # the longest (most specific) rule wins. If an Allow and Disallow rule have
  # equal length, Allow takes precedence.
  #
  # Defaults to allowing access if:
  # - robots.txt is missing or inaccessible
  # - No rules match the path
  # - No rule group exists for the user agent
  #
  # @param path [String] The URL path to check (e.g., "/archive" or "/posts/2024")
  # @param user_agent [String] The user agent to check rules for (default: "retrofeed")
  # @return [Boolean] true if path is allowed, false if disallowed
  #
  # @example
  #   robots.allowed?("/archive") # => true
  #   robots.allowed?("/admin") # => false (if disallowed)
  def allowed?(path, user_agent = DEFAULT_USER_AGENT)
    return true if path.blank?

    rule_group = rule_group_for(user_agent)
    return true unless rule_group

    matching_rule = most_specific_rule(rule_group[:rules], path)
    return true unless matching_rule

    # Only Allow rules explicitly permit access
    matching_rule.type == :allow
  rescue StandardError => e
    Rails.logger.warn("[RobotsTxt] allowed? failed, failing open: #{e.message}")
    true
  end

  # Returns the crawl-delay in seconds for the given user agent
  #
  # Checks user-agent specific rules first, then falls back to "*" rules,
  # then to the default delay.
  #
  # @param user_agent [String] The user agent to check crawl-delay for (default: "retrofeed")
  # @return [Float] Crawl delay in seconds
  #
  # @example
  #   robots.crawl_delay # => 5.0 (if specified in robots.txt)
  def crawl_delay(user_agent = DEFAULT_USER_AGENT)
    rule_group = rule_group_for(user_agent)
    rule_group&.dig(:crawl_delay) || DEFAULT_CRAWL_DELAY
  rescue StandardError => e
    Rails.logger.warn("[RobotsTxt] crawl_delay failed, using default: #{e.message}")
    DEFAULT_CRAWL_DELAY
  end

  private

  # Fetches robots.txt from the domain root
  #
  # Constructs the robots.txt URL from the domain URI and fetches it via HTTP.
  # Returns nil if robots.txt is missing (404) or if there's a network error,
  # allowing scraping to proceed (fail open).
  #
  # @return [String, nil] The robots.txt content, or nil if unavailable
  def fetch_and_parse
    robots_uri = Addressable::URI.new(
      scheme: @uri.scheme || "https",
      host: @uri.host,
      port: @uri.port,
      path: "/robots.txt"
    )

    Rails.logger.info("[RobotsTxt] Fetching #{robots_uri}")
    response = HTTParty.get(robots_uri.to_s, headers: { "User-Agent" => DEFAULT_USER_AGENT })

    if response.code == 200
      response.body
    else
      Rails.logger.info("[RobotsTxt] robots.txt not available for #{@uri.host} (status #{response.code}), failing open")
      nil
    end
  rescue HTTParty::Error, SocketError, Timeout::Error => e
    Rails.logger.warn("[RobotsTxt] Error fetching robots.txt for #{@uri.host}: #{e.message}")
    nil
  end

  # Parses robots.txt content into rule groups by user agent
  #
  # Parses standard robots.txt format:
  # - User-agent: <agent> (starts a new rule group)
  # - Allow: <path> (adds an allow rule)
  # - Disallow: <path> (adds a disallow rule)
  # - Crawl-delay: <seconds> (sets delay for the current group)
  #
  # Rules accumulate for the current user-agent group until a new User-agent
  # line is encountered.
  #
  # @param content [String] The robots.txt file content
  # @return [void]
  def parse(content)
    current_agents = []

    content.each_line do |line|
      stripped = line.strip
      # Skip blank lines and comments
      next if stripped.blank? || stripped.start_with?("#")

      if (ua_match = stripped.match(/\AUser-agent:\s*(.+)\z/i))
        # Start a new user-agent group
        agent = ua_match[1].strip.downcase
        current_agents = [ agent ]
        ensure_group(agent)
      elsif (allow_match = stripped.match(/\AAllow:\s*(.*)\z/i))
        # Add Allow rule to current user-agent(s)
        path = allow_match[1].strip
        next if current_agents.empty? || path.empty?
        current_agents.each { |ua| add_rule(ua, :allow, path) }
      elsif (disallow_match = stripped.match(/\ADisallow:\s*(.*)\z/i))
        # Add Disallow rule to current user-agent(s)
        path = disallow_match[1].strip
        next if current_agents.empty? || path.empty?
        current_agents.each { |ua| add_rule(ua, :disallow, path) }
      elsif (delay_match = stripped.match(/\ACrawl-delay:\s*(.+)\z/i))
        # Set crawl-delay for current user-agent(s)
        delay = delay_match[1].to_f
        next if current_agents.empty? || delay <= 0
        current_agents.each { |ua| set_crawl_delay(ua, delay) }
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[RobotsTxt] Failed to parse robots.txt for #{@uri.host}: #{e.message}")
  end

  # Ensures a rule group exists for the given user agent
  #
  # @param agent [String] The user agent string (normalized to lowercase)
  # @return [void]
  def ensure_group(agent)
    @rules_by_agent[agent] ||= { rules: [], crawl_delay: nil }
  end

  # Adds an Allow or Disallow rule for a user agent
  #
  # Normalizes paths to start with "/" and stores them in the rule group.
  #
  # @param agent [String] The user agent to add the rule for
  # @param type [:allow, :disallow] The rule type
  # @param path [String] The path pattern to match
  # @return [void]
  def add_rule(agent, type, path)
    ensure_group(agent)
    normalized_path = path.start_with?("/") ? path : "/#{path}"
    @rules_by_agent[agent][:rules] << Rule.new(type, normalized_path)
  end

  # Sets the crawl-delay for a user agent
  #
  # Only sets if not already set (first occurrence wins).
  #
  # @param agent [String] The user agent to set delay for
  # @param delay [Float] The delay in seconds
  # @return [void]
  def set_crawl_delay(agent, delay)
    ensure_group(agent)
    @rules_by_agent[agent][:crawl_delay] ||= delay
  end

  # Finds the rule group for a user agent, falling back to "*"
  #
  # @param user_agent [String] The user agent to find rules for
  # @return [Hash, nil] Rule group hash with :rules and :crawl_delay keys, or nil
  def rule_group_for(user_agent)
    return nil if @rules_by_agent.empty?

    normalized = user_agent.to_s.strip.downcase
    # Try exact match first, then fall back to "*"
    @rules_by_agent[normalized].presence || @rules_by_agent["*"]
  end

  # Finds the most specific matching rule for a path
  #
  # Uses longest-prefix matching: the rule with the longest matching path wins.
  # If two rules have equal length, Allow rules take precedence over Disallow.
  #
  # @param rules [Array<Rule>] Array of rules to search
  # @param path [String] The path to match against
  # @return [Rule, nil] The most specific matching rule, or nil if none match
  def most_specific_rule(rules, path)
    normalized_path = path.start_with?("/") ? path : "/#{path}"

    # Find all rules where the path starts with the rule pattern
    matching_rules = rules.select { |rule| normalized_path.start_with?(rule.path) }
    return nil if matching_rules.empty?

    # Sort by: 1) path length (longest first), 2) allow type (allow=1, disallow=0)
    matching_rules.max_by { |rule| [ rule.path.length, rule.type == :allow ? 1 : 0 ] }
  end
end
