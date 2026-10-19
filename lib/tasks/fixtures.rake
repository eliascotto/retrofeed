namespace :fixtures do
  desc "Generate fixture files from a live URL for mock testing"
  task :generate, [ :url, :fetch_articles, :site_name ] => :environment do |t, args|
    unless args[:url]
      puts "Usage: bin/rake fixtures:generate[https://example.com/archive]"
      puts ""
      puts "Options:"
      puts "  bin/rake fixtures:generate[url,false]        - Skip article fetching"
      puts "  bin/rake fixtures:generate[url,true,mysite]  - Custom site name"
      puts ""
      puts "Examples:"
      puts "  bin/rake fixtures:generate[https://overreacted.io/]"
      puts "  bin/rake fixtures:generate[https://macwright.com/writing,false]"
      next
    end

    url = args[:url]
    site_name = args[:site_name]
    fetch_articles = args[:fetch_articles].nil? || args[:fetch_articles] == "true"

    generator = FixtureGenerator.new(url, site_name: site_name)

    puts "=" * 60
    puts "Generating fixtures for: #{url}"
    puts "Site name: #{generator.site_name}"
    puts "Fetch articles: #{fetch_articles}"
    puts "=" * 60

    # Generate archive fixture
    generator.generate_archive_fixture

    # Optionally generate article fixtures
    if fetch_articles
      generator.generate_article_fixtures
    end

    # Update mock mapping
    generator.update_mock_mapping

    puts ""
    puts "Fixtures generated successfully!"
    puts "Location: #{generator.fixture_dir}"
  end

  desc "Generate article fixtures for an existing site (uses existing archive.html)"
  task :generate_articles, [ :site_name ] => :environment do |t, args|
    unless args[:site_name]
      puts "Usage: bin/rake fixtures:generate_articles[site_name]"
      puts ""
      puts "This task fetches article HTML for an existing fixture site."
      puts "It reads the archive.json to determine which articles to fetch."
      puts "Already fetched articles are skipped."
      puts ""
      puts "Available sites:"
      websites_path = Rails.root.join("test", "fixtures", "websites")
      Dir.glob(websites_path.join("*/archive.html")).each do |path|
        site = File.basename(File.dirname(path))
        articles_dir = websites_path.join(site, "articles")
        article_count = articles_dir.exist? ? Dir.glob(articles_dir.join("*.html")).count : 0
        puts "  - #{site} (#{article_count} articles)"
      end
      next
    end

    site_name = args[:site_name]
    websites_path = Rails.root.join("test", "fixtures", "websites")
    site_dir = websites_path.join(site_name)

    unless site_dir.exist?
      puts "ERROR: Site directory not found: #{site_dir}"
      next
    end

    archive_html_path = site_dir.join("archive.html")
    archive_json_path = site_dir.join("archive.json")

    unless archive_html_path.exist?
      puts "ERROR: archive.html not found for site: #{site_name}"
      next
    end

    unless archive_json_path.exist?
      puts "ERROR: archive.json not found for site: #{site_name}"
      puts "Run fixtures:generate first to create it."
      next
    end

    # Load articles from archive.json
    articles = JSON.parse(File.read(archive_json_path))
    puts "=" * 60
    puts "Generating article fixtures for: #{site_name}"
    puts "Total articles: #{articles.length}"
    puts "=" * 60

    articles_dir = site_dir.join("articles")
    FileUtils.mkdir_p(articles_dir)

    articles.each_with_index do |article, index|
      article_url = article["link"]
      slug = article_url.gsub(%r{https?://[^/]+}, "").gsub(%r{\A/|/\z}, "").gsub("/", "-").gsub(/[^a-zA-Z0-9\-_]/, "_")

      print "  [#{index + 1}/#{articles.length}] #{slug}... "

      article_path = articles_dir.join("#{slug}.html")
      if article_path.exist?
        puts "SKIP (already exists)"
        next
      end

      begin
        response = HTTParty.get(article_url)
        html = response.body

        File.binwrite(article_path, html)
        puts "OK (#{html.length} bytes)"
      rescue StandardError => e
        puts "FAILED: #{e.message}"
      end

      # Random delay to be polite to servers
      sleep(rand(0.5..1.5))
    end

    puts ""
    puts "Article fixtures saved to: #{articles_dir}"
  end

  desc "List all available fixture sites"
  task list: :environment do
    mapping_file = Rails.root.join("test", "fixtures", "files", "mock_mapping.yml")
    websites_path = Rails.root.join("test", "fixtures", "websites")

    unless File.exist?(mapping_file)
      puts "No mock_mapping.yml found."
      next
    end

    mapping = YAML.load_file(mapping_file)
    domains = mapping["domains"] || {}

    puts "Available fixture sites:"
    puts "-" * 40

    domains.each do |domain, site_name|
      site_dir = websites_path.join(site_name)
      archive_exists = File.exist?(site_dir.join("archive.html"))
      articles_dir = site_dir.join("articles")
      article_count = articles_dir.exist? ? Dir.glob(articles_dir.join("*.html")).count : 0

      status = archive_exists ? "[OK]" : "[MISSING]"
      articles_info = article_count > 0 ? " (#{article_count} articles)" : ""

      puts "  #{status} #{domain} -> #{site_name}#{articles_info}"
    end
  end

  desc "Download website fixtures from separate repository"
  task download: :environment do
    websites_path = Rails.root.join("test", "fixtures", "websites")
    repo_url = "git@github.com:eliascotto/retrofeed-web-fixtures.git"

    puts "=" * 60
    puts "Downloading website fixtures"
    puts "=" * 60
    puts ""

    if websites_path.exist? && Dir.exist?(websites_path.join(".git"))
      # Directory exists and is a git repo - pull latest
      puts "Updating existing fixtures..."
      Dir.chdir(websites_path) do
        system("git pull --ff-only") || abort("Failed to pull fixtures")
      end
    elsif websites_path.exist? && Dir.children(websites_path).any?
      # Directory exists with content but not a git repo
      puts "ERROR: #{websites_path} exists but is not a git repository."
      puts "Please remove it manually and run this task again:"
      puts "  rm -rf #{websites_path}"
      next
    else
      # Directory doesn't exist or is empty - clone
      puts "Cloning fixtures repository..."
      FileUtils.rm_rf(websites_path) if websites_path.exist?
      system("git clone #{repo_url} #{websites_path}") || abort("Failed to clone fixtures")
    end

    puts ""
    puts "Fixtures downloaded to: #{websites_path}"
    puts ""

    # Show status
    Rake::Task["fixtures:list"].invoke
  end

  desc "Show articles count for a single website"
  task :articles_count, [ :site_name ] => :environment do |t, args|
    unless args[:site_name]
      puts "Usage: bin/rake fixtures:print_articles_count[site_name]"
      puts ""
      puts "This task prints the number of articles for a single website."
      puts "It reads the archive.json to determine which articles to print."
    end

    site_name = args[:site_name]
    websites_path = Rails.root.join("test", "fixtures", "websites")
    site_dir = websites_path.join(site_name)

    unless site_dir.exist?
      puts "ERROR: Site directory not found: #{site_dir}"
      next
    end

    archive_json_path = site_dir.join("archive.json")

    unless archive_json_path.exist?
      puts "ERROR: archive.json not found for site: #{site_name}"
      next
    end

    articles = JSON.parse(File.read(archive_json_path))
    puts "Total articles: #{articles.length}"
    puts ""
    puts "Articles count for: #{site_name}"
    puts "=" * 60
  end

  desc "Print all the articles for a single website"
  task :print_articles, [ :site_name ] => :environment do |t, args|
    unless args[:site_name]
      puts "Usage: bin/rake fixtures:print_articles[site_name]"
      puts ""
      puts "This task prints all the articles for a single website."
      puts "It reads the archive.json to determine which articles to print."
    end

    site_name = args[:site_name]
    websites_path = Rails.root.join("test", "fixtures", "websites")
    site_dir = websites_path.join(site_name)

    unless site_dir.exist?
      puts "ERROR: Site directory not found: #{site_dir}"
      next
    end

    archive_json_path = site_dir.join("archive.json")

    unless archive_json_path.exist?
      puts "ERROR: archive.json not found for site: #{site_name}"
      next
    end

    articles = JSON.parse(File.read(archive_json_path))
    puts "=" * 60
    puts "Printing articles for: #{site_name}"
    puts "=" * 60

    articles.each do |article|
      puts "  #{article["title"]}"
    end

    puts ""
    puts "Total articles: #{articles.length}"
  end
end

# Helper class for generating fixtures
class FixtureGenerator
  attr_reader :url, :site_name, :fixture_dir

  WEBSITES_PATH = Rails.root.join("test", "fixtures", "websites") unless const_defined?(:WEBSITES_PATH)
  MAPPING_FILE = Rails.root.join("test", "fixtures", "files", "mock_mapping.yml") unless const_defined?(:MAPPING_FILE)

  def initialize(url, site_name: nil)
    @url = url
    @uri = URI.parse(url)
    @domain = @uri.host.sub(/\Awww\./i, "")
    @site_name = site_name || derive_site_name
    @fixture_dir = WEBSITES_PATH.join(@site_name)
  end

  def generate_archive_fixture
    puts "\nFetching archive HTML..."

    response = HTTParty.get(@url)
    html = response.body

    puts "  Fetched #{html.length} bytes"

    # Ensure directory exists
    FileUtils.mkdir_p(@fixture_dir)

    # Save archive HTML in binary mode to preserve encoding
    archive_path = @fixture_dir.join("archive.html")
    File.binwrite(archive_path, html)
    puts "  Saved to: #{archive_path}"

    # Generate expected JSON using the extraction logic
    puts "\nExtracting articles for expected JSON..."
    parsed_html = Nokogiri::HTML(html)

    if WebProcessor.contains_valid_archive?(parsed_html, @url)
      results = WebProcessor.extract_articles_from_archive(parsed_html, @url)
      articles = results.fetch(:articles, [])
      puts "  Found #{articles.length} articles"

      # Convert to expected JSON format
      expected_json = articles.map.with_index do |article, index|
        {
          "title" => article[:title],
          "link" => article[:url],
          "date" => article[:date]&.to_s,
          "tags" => article[:tags] || [],
          "order" => index + 1
        }
      end

      json_path = @fixture_dir.join("archive.json")
      File.write(json_path, JSON.pretty_generate(expected_json))
      puts "  Saved expected JSON to: #{json_path}"
    else
      puts "  WARNING: URL does not appear to be a valid archive"
    end

    @parsed_html = parsed_html
    @articles = articles
  end

  def generate_article_fixtures
    return unless @articles&.any?

    articles_dir = @fixture_dir.join("articles")
    FileUtils.mkdir_p(articles_dir)

    puts "\nFetching #{@articles.length} article fixtures..."

    @articles.each_with_index do |article, index|
      article_url = article[:url]
      slug = url_to_slug(article_url)

      print "  [#{index + 1}/#{@articles.length}] #{slug}... "

      article_path = articles_dir.join("#{slug}.html")
      if article_path.exist?
        puts "SKIP (already exists)"
        next
      end

      begin
        response = HTTParty.get(article_url)
        html = response.body

        File.binwrite(article_path, html)

        puts "OK (#{html.length} bytes)"
      rescue StandardError => e
        puts "FAILED: #{e.message}"
      end

      # Random delay to be polite to servers
      sleep(rand(0.5..1.5))
    end
  end

  def update_mock_mapping
    mapping = if File.exist?(MAPPING_FILE)
                YAML.load_file(MAPPING_FILE) || {}
    else
                {}
    end

    mapping["domains"] ||= {}
    mapping["archive_paths"] ||= {}

    # Add domain mapping if not present
    unless mapping["domains"][@domain]
      mapping["domains"][@domain] = @site_name
      puts "\nAdded domain mapping: #{@domain} -> #{@site_name}"
    end

    # Add archive path if not present
    archive_path = @uri.path.chomp("/")
    archive_path = "/" if archive_path.empty?

    mapping["archive_paths"][@site_name] ||= []
    unless mapping["archive_paths"][@site_name].include?(archive_path)
      mapping["archive_paths"][@site_name] << archive_path
      # Also add version with trailing slash
      mapping["archive_paths"][@site_name] << "#{archive_path}/" unless archive_path == "/"
      puts "Added archive path for #{@site_name}: #{archive_path}"
    end

    # Write updated mapping
    File.write(MAPPING_FILE, mapping.to_yaml)
  end

  private

  def derive_site_name
    # Convert domain to a simple name
    # e.g., "macwright.com" -> "macwright"
    #       "journal.stuffwithstuff.com" -> "journal"
    parts = @domain.split(".")
    if parts.first == "www"
      parts[1]
    elsif parts.length > 2
      parts.first
    else
      parts.first
    end
  end

  def url_to_slug(article_url)
    uri = URI.parse(article_url)
    path = uri.path.gsub(%r{\A/|/\z}, "").gsub("/", "-")
    # Sanitize for filename
    path.gsub(/[^a-zA-Z0-9\-_]/, "_")
  end
end
