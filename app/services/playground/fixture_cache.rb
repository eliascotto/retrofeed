# Manages HTML fixture caching for the playground
#
# Stores fetched HTML pages in tmp/playground_fixtures/ for offline testing.
# Each fixture has a sidecar .meta.json file with fetch metadata.
#
# Usage:
#   Playground::FixtureCache.find_fixture("https://example.com/blog")
#   Playground::FixtureCache.save_fixture("https://example.com/blog", html, metadata)
#   Playground::FixtureCache.list_fixtures("example.com")
#
class Playground::FixtureCache
  FIXTURES_PATH = Rails.root.join("tmp", "playground_fixtures")

  class << self
    # Finds a fixture for the given URL
    #
    # @param url [String] The URL to find a fixture for
    # @return [String, nil] The fixture file path if exists, nil otherwise
    def find_fixture(url)
      path = fixture_path(url)
      return path if path && File.exist?(path)

      nil
    end

    # Saves HTML content and metadata as a fixture
    #
    # @param url [String] The URL being cached
    # @param html [String] The HTML content
    # @param metadata [Hash] Optional metadata (http_status, headers, etc.)
    # @return [String] The path where the fixture was saved
    def save_fixture(url, html, metadata = {})
      path = fixture_path(url)
      ensure_directory_exists(File.dirname(path))

      # Save HTML content in binary mode to preserve encoding from HTTP response
      File.binwrite(path, html)

      # Save metadata sidecar file
      meta = {
        url: url,
        fetched_at: Time.current.iso8601,
        file_size: html.bytesize,
        http_status: metadata[:http_status] || 200,
        content_type: metadata[:content_type],
        headers: metadata[:headers]
      }.compact

      File.write(metadata_path(url), JSON.pretty_generate(meta))

      Rails.logger.info("[Playground::FixtureCache] Saved fixture for #{url} (#{html.bytesize} bytes)")
      path
    end

    # Returns the fixture file path for a URL
    #
    # @param url [String] The URL
    # @return [String] The fixture file path
    def fixture_path(url)
      uri = parse_url(url)
      return nil unless uri

      domain = uri.host.sub(/\Awww\./i, "")
      path_part = uri.path.presence || "/"

      # Generate hash prefix to prevent collisions
      hash_prefix = Digest::SHA256.hexdigest(path_part)[0..7]
      sanitized_path = sanitize_path(path_part)

      FIXTURES_PATH.join(domain, "#{hash_prefix}_#{sanitized_path}.html").to_s
    end

    # Returns the metadata sidecar file path for a URL
    #
    # @param url [String] The URL
    # @return [String] The metadata file path
    def metadata_path(url)
      fixture = fixture_path(url)
      return nil unless fixture

      fixture.sub(/\.html\z/, ".meta.json")
    end

    # Loads metadata for a fixture
    #
    # @param url [String] The URL
    # @return [Hash, nil] The metadata hash, or nil if not found
    def load_metadata(url)
      path = metadata_path(url)
      return nil unless path && File.exist?(path)

      JSON.parse(File.read(path), symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # Lists all cached fixtures, optionally filtered by domain
    #
    # @param domain [String, nil] Optional domain to filter by
    # @return [Array<Hash>] Array of fixture info hashes
    def list_fixtures(domain = nil)
      return [] unless FIXTURES_PATH.exist?

      fixtures = []

      dirs = if domain.present?
               domain_path = FIXTURES_PATH.join(domain)
               domain_path.exist? ? [ domain_path ] : []
      else
               FIXTURES_PATH.children.select(&:directory?)
      end

      dirs.each do |domain_dir|
        domain_name = domain_dir.basename.to_s

        Dir.glob(domain_dir.join("*.html")).each do |html_file|
          meta_file = html_file.sub(/\.html\z/, ".meta.json")
          metadata = if File.exist?(meta_file)
                       JSON.parse(File.read(meta_file), symbolize_names: true) rescue {}
          else
                       {}
          end

          fixtures << {
            domain: domain_name,
            path: html_file,
            url: metadata[:url],
            fetched_at: metadata[:fetched_at],
            file_size: File.size(html_file),
            filename: File.basename(html_file)
          }
        end
      end

      fixtures.sort_by { |f| [ f[:domain], f[:fetched_at] || "" ] }
    end

    # Lists all domains that have cached fixtures
    #
    # @return [Array<String>] Array of domain names
    def list_domains
      return [] unless FIXTURES_PATH.exist?

      FIXTURES_PATH.children
                   .select(&:directory?)
                   .map { |d| d.basename.to_s }
                   .sort
    end

    # Clears a specific fixture
    #
    # @param url [String] The URL to clear
    # @return [Boolean] True if deleted, false if not found
    def clear_fixture(url)
      html_path = fixture_path(url)
      meta_path = metadata_path(url)

      deleted = false

      if html_path && File.exist?(html_path)
        File.delete(html_path)
        deleted = true
      end

      if meta_path && File.exist?(meta_path)
        File.delete(meta_path)
      end

      # Clean up empty domain directories
      if html_path
        domain_dir = File.dirname(html_path)
        if Dir.exist?(domain_dir) && Dir.empty?(domain_dir)
          Dir.rmdir(domain_dir)
        end
      end

      Rails.logger.info("[Playground::FixtureCache] Cleared fixture for #{url}") if deleted
      deleted
    end

    # Clears all fixtures for a domain
    #
    # @param domain [String] The domain to clear
    # @return [Integer] Number of fixtures deleted
    def clear_domain(domain)
      domain_path = FIXTURES_PATH.join(domain)
      return 0 unless domain_path.exist?

      count = Dir.glob(domain_path.join("*.html")).count
      FileUtils.rm_rf(domain_path)

      Rails.logger.info("[Playground::FixtureCache] Cleared #{count} fixtures for domain #{domain}")
      count
    end

    # Clears all fixtures
    #
    # @return [Integer] Number of fixtures deleted
    def clear_all_fixtures
      return 0 unless FIXTURES_PATH.exist?

      count = Dir.glob(FIXTURES_PATH.join("**", "*.html")).count
      FileUtils.rm_rf(FIXTURES_PATH)

      Rails.logger.info("[Playground::FixtureCache] Cleared all #{count} fixtures")
      count
    end

    # Returns fixture statistics
    #
    # @return [Hash] Statistics about cached fixtures
    def stats
      return { domains: 0, fixtures: 0, total_size: 0 } unless FIXTURES_PATH.exist?

      domains = list_domains
      fixtures = list_fixtures
      total_size = fixtures.sum { |f| f[:file_size] || 0 }

      {
        domains: domains.count,
        fixtures: fixtures.count,
        total_size: total_size,
        total_size_human: human_file_size(total_size)
      }
    end

    private
      def parse_url(url)
        URI.parse(url)
      rescue URI::InvalidURIError
        nil
      end

      def sanitize_path(path)
        # Remove leading/trailing slashes
        sanitized = path.gsub(%r{\A/|/\z}, "")
        # Replace slashes with underscores
        sanitized = sanitized.gsub("/", "_")
        # Replace special characters with underscores
        sanitized = sanitized.gsub(/[^a-zA-Z0-9\-_]/, "_")
        # Collapse multiple underscores
        sanitized = sanitized.gsub(/_+/, "_")
        # Remove leading/trailing underscores
        sanitized = sanitized.gsub(/\A_|_\z/, "")
        # Default to "index" for empty paths
        sanitized.presence || "index"
      end

      def ensure_directory_exists(path)
        FileUtils.mkdir_p(path) unless Dir.exist?(path)
      end

      def human_file_size(size)
        units = %w[B KB MB GB]
        unit_index = 0

        while size >= 1024 && unit_index < units.length - 1
          size /= 1024.0
          unit_index += 1
        end

        "#{size.round(1)} #{units[unit_index]}"
      end
  end
end
