#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to find empty article HTML files in fixtures and scrape them
#
# Usage: rails runner script/fill_empty_articles.rb

require 'yaml'
require 'json'
require 'fileutils'

FIXTURES_DIR = File.join(__dir__, '..', 'test', 'fixtures', 'websites').freeze
MOCK_MAPPING = File.join(__dir__, '..', 'test', 'fixtures', 'files', 'mock_mapping.yml').freeze

def load_mock_mapping
  YAML.load_file(MOCK_MAPPING)
end

def find_archive_json(site_dir)
  archive_json = File.join(site_dir, 'archive.json')
  return archive_json if File.exist?(archive_json)
  nil
end

def load_archive_json(archive_path)
  JSON.parse(File.read(archive_path))
rescue JSON::ParserError => e
  warn "Failed to parse #{archive_path}: #{e.message}"
  nil
end

def article_file_empty?(site_dir, file_path)
  full_path = File.join(site_dir, file_path)
  return true unless File.exist?(full_path)

  content = File.read(full_path)
  content.strip.empty?
end

def fetch_html(url)
  WebFetcher::Live.fetch(url)
rescue WebFetcher::FetchError => e
  raise "Failed to fetch #{url}: #{e.message}"
end

def save_article_html(site_dir, file_path, html)
  full_path = File.join(site_dir, file_path)
  dir = File.dirname(full_path)
  FileUtils.mkdir_p(dir)
  File.write(full_path, html, mode: 'w')
end

def scrape_and_save_article(website, url, site_dir, file_path)
  puts "Fetching: #{url}"

  html = fetch_html(url)
  save_article_html(site_dir, file_path, html)

  puts "  ✓ Saved to #{file_path}"
  true
rescue StandardError => e
  puts "  ✗ Failed: #{e.message}"
  false
end

def main
  mapping = load_mock_mapping
  domains = mapping['domains'] || {}

  empty_articles = []

  domains.each do |domain, site_name|
    # Get the site directory
    site_dir = File.join(FIXTURES_DIR, site_name)
    next unless Dir.exist?(site_dir)

    # Get the archive JSON file
    archive_path = find_archive_json(site_dir)
    next unless archive_path

    # Load the archive JSON file
    puts "\nChecking #{site_name}..."
    archive_data = load_archive_json(archive_path)
    next unless archive_data

    archive_data.each do |article|
      file_path = article['file']
      link = article['link']

      next unless file_path && link

      # Check if the article file is empty and add it to the empty articles list
      if article_file_empty?(site_dir, file_path)
        empty_articles << {
          website: site_name,
          file: file_path,
          url: link,
          site_dir: site_dir
        }
        puts "  Found empty: #{file_path}"
      end
    end
  end

  if empty_articles.empty?
    puts "\nNo empty articles found!"
    return
  end

  puts "\n\nFound #{empty_articles.length} empty article(s):"
  empty_articles.each do |article|
    puts "  - #{article[:website]}: #{article[:file]}"
  end

  puts "\nScraping empty articles..."
  puts "=" * 80

  success_count = 0
  fail_count = 0

  empty_articles.each_with_index do |article, index|
    puts "\n[#{index + 1}/#{empty_articles.length}] #{article[:file]}"
    if scrape_and_save_article(article[:website], article[:url], article[:site_dir], article[:file])
      success_count += 1
    else
      fail_count += 1
    end
  end

  puts "\n" + "=" * 80
  puts "Summary:"
  puts "  Total: #{empty_articles.length}"
  puts "  Success: #{success_count}"
  puts "  Failed: #{fail_count}"
end

main if __FILE__ == $PROGRAM_NAME
