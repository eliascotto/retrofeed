
MAPPING_FILE = Rails.root.join("test", "fixtures", "files", "mock_mapping.yml")
WEBSITES_PATH = Rails.root.join("test", "fixtures", "websites")

Rails.logger.level = Logger::ERROR  # or INFO, WARN, ERROR, FATAL

class FixtureCompletenessTest
  def initialize
    @mapping_file = MAPPING_FILE
    @websites_path = WEBSITES_PATH
    @website_configs = load_website_configs.freeze

    # Check if the mapping file exists
    raise "ERROR: mock_mapping.yml not found at #{@mapping_file}" unless File.exist?(@mapping_file)

    # Check if the websites fixture folder exists
    raise "ERROR: websites fixture folder not found at #{@websites_path}" unless File.exist?(@websites_path)

    # Check if the websites fixture folder contains at least one site director
    site_dirs = Dir.glob(@websites_path.join("*")).select { |f| File.directory?(f) }
    raise "ERROR: Websites fixture folder should contain at least one site directory" unless site_dirs.any?
  end

  # Load website configurations
  def load_website_configs
    mapping = YAML.load_file(MAPPING_FILE)
    domains = mapping["domains"] || {}
    archive_paths = mapping["archive_paths"] || {}

    domains.map do |domain, site_name|
      site_archive_paths = archive_paths[site_name] || []
      archive_path = site_archive_paths.first&.chomp("/") || "/"

      {
        name: site_name,
        domain: domain,
        base_url: "https://#{domain}#{archive_path}"
      }
    end
  end

  def load_articles_for_site(site_name)
    archive_json = @websites_path.join(site_name, "archive.json")
    raise "ERROR: archive.json not found for #{site_name}" unless File.exist?(archive_json)

    JSON.parse(File.read(archive_json))
  end

  def validate_article_fixtures(site_name, articles)
    articles.each do |article|
      fixture_file = article["file"]
      # Raise an error if no fixture file is specified
      raise "ERROR: No fixture file specified for #{article["link"]}" unless fixture_file

      fixture_path = @websites_path.join(site_name, fixture_file)
      raise "ERROR: Fixture file not found for #{article["link"]}" unless File.exist?(fixture_path)
    end
  end

  def process_article(article, out_prefix: nil, index: nil, total: nil)
    fixture_file = article["file"]
    fixture_url = article["link"]

    # Fetch the content of the fixture file
    html_content = WebFetcher::Mock.fetch(fixture_url)
    if html_content.nil? || html_content.empty?
      raise "ERROR: Empty content for #{fixture_file} (#{fixture_url})"
    end

    # Convert the content to markdown
    result = WebProcessor.extract_article_content(fixture_url, html: html_content)

    # Log the result
    if result && result[:content]
      if out_prefix && index && total && index % 10 == 0
        puts "#{out_prefix} Processed #{index + 1}/#{total}"
      end
      true
    elsif result && result[:error]
      error_msg = "#{out_prefix || ''} Failed to process #{fixture_file}: #{result[:error]}"
      puts error_msg.strip
      false
    else
      error_msg = "#{out_prefix || ''} Unknown error #{fixture_file}: #{result&.dig(:error) || 'unknown error'}"
      puts error_msg.strip
      false
    end
  end

  def run
    puts "Running fixture completeness test..."

    WebFetcher::Mock.clear_cache! if WebFetcher::Mock.respond_to?(:clear_cache!)

    @website_configs.each_with_index do |config, index|
      site_name = config[:name]
      out_prefix = "#{index + 1}/#{@website_configs.length} #{site_name}"

      articles = load_articles_for_site(site_name)
      validate_article_fixtures(site_name, articles)

      puts "#{out_prefix} Processing..."

      articles.each_with_index do |article, article_index|
        success = process_article(article, out_prefix: out_prefix, index: article_index, total: articles.length)
        return unless success
      end
    end
  end

  def run_single_article(site_name, article_path)
    # Validate site_name
    site_config = @website_configs.find { |config| config[:name] == site_name }
    raise "ERROR: Site '#{site_name}' not found in website configs" unless site_config

    site_dir = @websites_path.join(site_name)
    raise "ERROR: Site directory not found for #{site_name}" unless File.exist?(site_dir)

    # Load articles for the site
    articles = load_articles_for_site(site_name)

    # Find article by matching the file path
    # article_path is like "2008-02-26-avoiding-overload-hell-in-c.html"
    # but file field is like "articles/2008-02-26-avoiding-overload-hell-in-c.html"
    article = articles.find do |a|
      file = a["file"]
      next false unless file

      # Match if file ends with /article_path or equals article_path
      file.end_with?("/#{article_path}") || file == article_path || File.basename(file) == article_path
    end

    raise "ERROR: Article with path '#{article_path}' not found in archive.json for #{site_name}" unless article

    # Validate the fixture file exists
    validate_article_fixtures(site_name, [ article ])

    puts "Processing article: #{article["title"]}"
    puts "  File: #{article["file"]}"
    puts "  URL: #{article["link"]}"

    WebFetcher::Mock.clear_cache! if WebFetcher::Mock.respond_to?(:clear_cache!)

    success = process_article(article, out_prefix: "#{site_name}")
    exit(success ? 0 : 1)
  end
end

fct = FixtureCompletenessTest.new

if ARGV.length == 2
  site_name = ARGV[0]
  article_path = ARGV[1]
  fct.run_single_article(site_name, article_path)
elsif ARGV.length == 0
  fct.run
else
  puts "A script to test the completeness of the fixture files. Can run the entire fixture set or a single article."
  puts ""
  puts "Usage:\n"
  puts "  rails runner script/fixture_completeness_test.rb [site_name] [article_path]"
  puts "  rails runner script/fixture_completeness_test.rb"
  exit 1
end
