# Mock HTTP fetcher that returns fixture data instead of making real HTTP requests
#
# Fixture data is loaded from test/fixtures/websites/ based on domain mapping in mock_mapping.yml.
#
# Fixture structure:
#   test/fixtures/websites/{site_name}/archive.html - archive page HTML
#   test/fixtures/websites/{site_name}/articles/{slug}.html - article page HTML (optional)
#
module WebFetcher
  module Mock
    FIXTURES_PATH = Rails.root.join("test", "fixtures", "websites")
    MAPPING_FILE = Rails.root.join("test", "fixtures", "files", "mock_mapping.yml")

    # Fetches HTML content from fixtures based on URL
    #
    # Returns the same format as WebFetcher::Live.fetch for consistency.
    # In mock mode, final_url is always the same as the requested URL since
    # there are no real HTTP redirects.
    #
    # @param url [String] The URL to fetch
    # @return [Hash] Hash with :content (String) and :final_url (String)
    # @raise [WebFetcher::FixtureNotFoundError] If no fixture exists for the URL
    def self.fetch(url)
      Rails.logger.info("[WebFetcher::Mock] Mock fetching: #{url}")

      fixture_path = find_fixture_for_url(url)

      # Fallback: try archive.json URL-to-file mapping for external domain URLs
      if fixture_path.nil? || !File.exist?(fixture_path)
        fixture_path = find_fixture_via_archive_json(url)
      end

      if fixture_path && File.exist?(fixture_path)
        content = File.binread(fixture_path)
        Rails.logger.info("[WebFetcher::Mock] Loaded fixture from #{fixture_path} (#{content.length} bytes)")
        { content: content, final_url: url }
      else
        Rails.logger.info("[WebFetcher::Mock] No fixture for #{url}, falling back to live fetch")
        WebFetcher::Live.fetch(url)
      end
    end

    # Performs a mock HEAD request
    # Returns 200 if a fixture exists for the URL, 404 otherwise
    #
    # Returns the same format as WebFetcher::Live.head for consistency.
    # In mock mode, final_url is always the same as the requested URL.
    #
    # @param url [String] The URL to probe
    # @return [Hash] Hash with :status (Integer), :headers (Hash), and :final_url (String)
    def self.head(url)
      Rails.logger.info("[WebFetcher::Mock] Mock HEAD request: #{url}")

      fixture_path = find_fixture_for_url(url)
      fixture_path ||= find_fixture_via_archive_json(url)

      if fixture_path && File.exist?(fixture_path)
        Rails.logger.info("[WebFetcher::Mock] HEAD returning 200 (fixture exists)")
        { status: 200, headers: { "content-type" => "text/html" }, final_url: url }
      else
        Rails.logger.info("[WebFetcher::Mock] No fixture for #{url}, falling back to live HEAD")
        WebFetcher::Live.head(url)
      end
    end

    # Finds the fixture file path for a given URL
    #
    # @param url [String] The URL to find a fixture for
    # @return [Pathname, nil] The path to the fixture file, or nil if not found
    def self.find_fixture_for_url(url)
      uri = URI.parse(url)
      domain = uri.host.sub(/\Awww\./i, "")
      path = uri.path

      mapping = load_mapping
      site_name = mapping.dig("domains", domain)

      unless site_name
        Rails.logger.warn("[WebFetcher::Mock] No mapping found for domain: #{domain}")
        return nil
      end

      site_fixtures = FIXTURES_PATH.join(site_name)

      # Check if this is a favicon request
      if is_favicon_url?(path)
        return find_favicon_fixture(site_fixtures, path)
      end

      # Check if this is an archive URL (matches the archive_url pattern in mapping)
      archive_paths = mapping.dig("archive_paths", site_name) || []
      if archive_paths.any? { |archive_path| path == archive_path || path == "#{archive_path}/" }
        return site_fixtures.join("archive.html")
      end

      # Otherwise, try to find an article fixture
      # Convert URL path to a fixture filename
      slug = path_to_slug(path)
      article_fixture = site_fixtures.join("articles", "#{slug}.html")

      if File.exist?(article_fixture)
        return article_fixture
      end

      # Try to find a date-prefixed fixture (e.g., 2019-03-16-article-slug.html)
      # This handles fixtures where filenames include publication dates
      articles_dir = site_fixtures.join("articles")
      if articles_dir.exist?
        matching_files = Dir.glob(articles_dir.join("*-#{slug}.html"))
        if matching_files.any?
          return Pathname.new(matching_files.first)
        end
      end

      # Fall back to archive.html only for exact archive URL matches
      # Don't fall back for article-like paths that just happen to share prefixes
      archive_fixture = site_fixtures.join("archive.html")
      if File.exist?(archive_fixture) && is_exact_archive_url?(path, archive_paths)
        return archive_fixture
      end

      nil
    end

    # Checks if a URL path is a favicon request
    #
    # @param path [String] The URL path
    # @return [Boolean] True if this is a favicon request
    def self.is_favicon_url?(path)
      return false if path.blank?

      basename = File.basename(path).downcase
      basename.include?("favicon") || basename.match?(/\A(apple-touch-icon|icon).*\.(ico|png|svg|gif|jpg|jpeg|webp)\z/i)
    end

    # Finds a favicon fixture file for a site
    #
    # @param site_fixtures [Pathname] Path to the site's fixtures directory
    # @param path [String] The URL path (used to determine preferred extension)
    # @return [Pathname, nil] The path to the favicon fixture file, or nil if not found
    def self.find_favicon_fixture(site_fixtures, path)
      # Try to match the requested extension first
      extension = File.extname(path).downcase
      if extension.present?
        direct_match = site_fixtures.join("favicon#{extension}")
        return direct_match if File.exist?(direct_match)
      end

      # Look for any favicon file in the site fixtures directory
      favicon_patterns = %w[favicon.ico favicon.png favicon.svg favicon.gif favicon.jpg favicon.jpeg favicon.webp]
      favicon_patterns.each do |pattern|
        favicon_path = site_fixtures.join(pattern)
        return favicon_path if File.exist?(favicon_path)
      end

      Rails.logger.debug("[WebFetcher::Mock] No favicon fixture found in #{site_fixtures}")
      nil
    end

    # Fallback: search all site archive.json files for URL-to-file mapping
    # This handles external domain URLs (e.g., codemirror.net articles for marijnhaverbeke.nl)
    #
    # @param url [String] The URL to find a fixture for
    # @return [Pathname, nil] The path to the fixture file, or nil if not found
    def self.find_fixture_via_archive_json(url)
      mapping = load_mapping
      domains = mapping.dig("domains") || {}

      domains.each_value do |site_name|
        site_fixtures = FIXTURES_PATH.join(site_name)
        archive_json = site_fixtures.join("archive.json")
        next unless File.exist?(archive_json)

        begin
          articles = JSON.parse(File.read(archive_json))
          article_entry = articles.find { |a| a["link"] == url }
          if article_entry && article_entry["file"]
            fixture_path = site_fixtures.join(article_entry["file"])
            return fixture_path if File.exist?(fixture_path)
          end
        rescue JSON::ParserError
          next
        end
      end

      nil
    end

    # Converts a URL path to a fixture slug
    #
    # @param path [String] The URL path (e.g., "/2024/01/15/my-article")
    # @return [String] The fixture slug (e.g., "2024-01-15-my-article")
    def self.path_to_slug(path)
      # Remove leading/trailing slashes and replace remaining slashes with dashes
      slug = path.gsub(%r{\A/|/\z}, "").gsub("/", "-")
      # Remove .html extension to avoid double-extension in glob pattern
      slug.sub(/\.html\z/, "")
    end

    # Checks if a path looks like an archive URL
    #
    # @param path [String] The URL path
    # @return [Boolean] True if the path looks like an archive URL
    def self.is_likely_archive_url?(path)
      archive_patterns = %w[/archive /archives /writing /blog /posts]
      archive_patterns.any? { |pattern| path.start_with?(pattern) || path == "/" }
    end

    # Checks if a path exactly matches one of the archive paths
    # More strict than is_likely_archive_url? to avoid false positives
    #
    # @param path [String] The URL path
    # @param archive_paths [Array<String>] The configured archive paths for this site
    # @return [Boolean] True if the path exactly matches an archive URL
    def self.is_exact_archive_url?(path, archive_paths)
      return false if archive_paths.empty?

      # Check for exact match with configured archive paths
      archive_paths.any? { |archive_path| path == archive_path || path == "#{archive_path}/" }
    end

    # Loads the domain mapping from mock_mapping.yml
    #
    # @return [Hash] The mapping configuration
    def self.load_mapping
      return @mapping if defined?(@mapping) && !Rails.env.test?

      if File.exist?(MAPPING_FILE)
        @mapping = YAML.load_file(MAPPING_FILE) || {}
      else
        Rails.logger.warn("[WebFetcher::Mock] No mock_mapping.yml found at #{MAPPING_FILE}")
        @mapping = {}
      end

      @mapping
    end

    # Clears the cached mapping (useful for testing)
    def self.clear_cache!
      remove_instance_variable(:@mapping) if defined?(@mapping)
    end
  end
end
