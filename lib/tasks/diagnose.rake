# Diagnostic rake tasks for debugging website processing issues
namespace :diagnose do
  desc "Diagnose stuck website processing. Usage: rake diagnose:website[domain]"
  task :website, [ :domain ] => :environment do |_t, args|
    domain = args[:domain]
    if domain.blank?
      puts "Usage: rake diagnose:website[domain]"
      puts "Example: rake diagnose:website[overreacted.io]"
      exit 1
    end

    website = Website.find_by(domain: domain)
    unless website
      puts "Website not found: #{domain}"
      exit 1
    end

    puts "=== Website Diagnosis: #{domain} ==="
    puts "ID: #{website.id}"
    puts "Name: #{website.name || '(not set)'}"
    puts "Archive URL: #{website.archive_url}"
    puts "Processing Status: #{website.processing_status}"
    puts "Processing Started: #{website.processing_started_at || 'N/A'}"
    puts "Processing Failed: #{website.processing_failed_at || 'N/A'}"
    puts "Processing Error: #{website.processing_error_message || 'N/A'}"
    puts "Last Crawled: #{website.last_crawled_at || 'N/A'}"
    puts ""

    stats = website.progress_stats
    puts "=== Article Stats ==="
    puts "Total: #{stats[:total]}"
    puts "Processed (with content): #{stats[:processed]}"
    puts "Failed: #{stats[:failed]}"
    puts "Pending: #{stats[:pending]}"
    puts "Percentage: #{stats[:percentage]}%"
    puts "Is Processing: #{stats[:is_processing]}"
    puts "Has Errors: #{stats[:has_errors]}"
    puts "Error Message: #{stats[:error_message] || 'N/A'}"
    puts ""

    puts "=== Recent Errors (ContentErrorGroup) ==="
    # Find errors by domain OR by article association
    # Using two separate queries since .or requires structurally compatible relations
    domain_error_ids = ContentErrorGroup.where(domain: domain).pluck(:id)
    article_error_ids = ContentErrorGroup
      .joins("INNER JOIN articles ON content_error_groups.subject_id = articles.id AND content_error_groups.subject_type = 'Article'")
      .where(articles: { website_id: website.id })
      .pluck(:id)
    all_error_ids = (domain_error_ids + article_error_ids).uniq
    errors = ContentErrorGroup
      .where(id: all_error_ids)
      .order(last_seen_at: :desc)
      .limit(10)

    if errors.empty?
      puts "(no errors recorded)"
    else
      errors.each do |e|
        puts "- [#{e.phase}/#{e.operation}] #{e.message.to_s.truncate(80)}"
        puts "  Occurrences: #{e.occurrences_count}, Last seen: #{e.last_seen_at}"
        puts "  Exception: #{e.exception_class}" if e.exception_class.present?
        puts ""
      end
    end

    puts "=== Failed Articles (sample) ==="
    failed = website.articles.where.not(content_fetch_failed_at: nil).limit(10)
    if failed.empty?
      puts "(no failed articles)"
    else
      failed.each do |a|
        puts "- #{a.url.truncate(60)}"
        puts "  Reason: #{a.failure_reason || 'Unknown'}"
        puts "  Failed at: #{a.content_fetch_failed_at}"
        puts ""
      end
    end

    puts "=== Recommendations ==="
    if stats[:has_errors] && stats[:failed] > stats[:processed]
      puts "- Most articles failed. Check extractor server status:"
      puts "  curl http://localhost:3880/health"
    end

    if website.processing_status == "extracting" && !stats[:is_processing]
      puts "- Status is 'extracting' but not actually processing."
      puts "  Consider running: Website.find(#{website.id}).update!(processing_status: 'pending')"
    end
  end

  desc "List all websites with processing issues"
  task stuck: :environment do
    puts "=== Websites with Processing Issues ==="
    puts ""

    # Websites stuck in extracting/crawling for too long
    stuck_processing = Website.where(processing_status: %w[extracting crawling])
                              .where("processing_started_at < ?", 30.minutes.ago)
    if stuck_processing.any?
      puts "Stuck in processing (> 30 minutes):"
      stuck_processing.each do |w|
        puts "  - #{w.domain} (#{w.processing_status}) - started #{time_ago_in_words(w.processing_started_at)} ago"
      end
      puts ""
    end

    # Websites marked as failed
    failed = Website.where(processing_status: "failed")
    if failed.any?
      puts "Failed websites:"
      failed.each do |w|
        puts "  - #{w.domain}: #{w.processing_error_message.to_s.truncate(60)}"
      end
      puts ""
    end

    # Websites marked as partial
    partial = Website.where(processing_status: "partial")
    if partial.any?
      puts "Partial completion (some articles failed):"
      partial.each do |w|
        stats = w.progress_stats
        puts "  - #{w.domain}: #{stats[:processed]} processed, #{stats[:failed]} failed"
      end
      puts ""
    end

    if stuck_processing.empty? && failed.empty? && partial.empty?
      puts "No websites with processing issues found."
    end
  end

  desc "Check extractor server health"
  task extractor: :environment do
    puts "=== Extractor Server Health ==="
    puts "Host: #{ENV.fetch('EXTRACTOR_HOST', 'localhost')}"
    puts "Port: #{ENV.fetch('EXTRACTOR_PORT', 3880)}"
    puts ""

    begin
      health = ExtractorClient.health
      puts "Status: #{health[:status]}"
      puts "Uptime: #{health[:uptime]}s" if health[:uptime]
      puts "Memory: #{health[:memory]}" if health[:memory]
    rescue ExtractorClient::ExtractorError => e
      puts "ERROR: #{e.message}"
      puts ""
      puts "The extractor server is not responding."
      puts "Start it with: node node_scripts/extractor.js"
    end
  end

  private

  def time_ago_in_words(time)
    return "unknown" unless time

    seconds = Time.current - time
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m"
    elsif seconds < 86400
      "#{(seconds / 3600).round}h"
    else
      "#{(seconds / 86400).round}d"
    end
  end
end
