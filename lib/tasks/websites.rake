namespace :websites do
  module ObservabilityTasks
    def self.silence_sql
      logger = ActiveRecord::Base.logger
      return yield unless logger

      original_level = logger.level
      logger.level = Logger::WARN
      yield
    ensure
      logger.level = original_level if logger
    end

    def self.section(title)
      puts "\n#{title}"
      puts "-" * 80
    end

    def self.safe(value)
      value.present? ? value : "(nil)"
    end
  end

  desc "List sites"
  task list: :environment do
    puts "Sites:"
    puts "=" * 60
    Website.all.each do |site|
      puts "  - #{site.id} #{site.domain} #{site.name}"
    end
    puts "=" * 60
  end

  desc "Refresh all sites (hard refresh, enqueues a forced archive re-crawl for each)"
  task refresh: :environment do
    Website.all.each do |site|
      puts "Queueing refresh for #{site.domain}..."
      site.refresh_later
    end
    puts "Done. #{Website.count} site(s) queued."
  end

  desc "Refresh a single site by ID (hard refresh)"
  task :refresh_site, [ :id ] => :environment do |t, args|
    unless args[:id]
      puts "Usage:"
      puts "  bin/rails 'websites:refresh_site[1]'"
      puts "  bin/rails websites:refresh_site\\[1\\]  (for zsh)"
      next
    end

    site = Website.find_by(id: args[:id])

    unless site
      puts "ERROR: Site not found with id: #{args[:id]}"
      next
    end

    puts "Queueing refresh for #{site.domain}..."
    site.refresh_later
    puts "Done."
  end

  desc "Show single site"
  task :show, [ :id ] => :environment do |t, args|
    unless args[:id]
      puts "Usage:"
      puts "  bin/rake sites:show[1]"
      puts "  bin/rails 'sites:show[1]'  (for zsh)"
      puts "  bin/rails sites:show\\[1\\]  (for zsh)"
      puts ""
      puts "Example:"
      puts "  bin/rake sites:show[1]"
      next
    end
    id = args[:id]
    site = Website.find(id)

    unless site
      puts "Site not found with id: #{id}"
      puts "Available sites:"
      Website.all.each do |s|
        puts "  - #{s.id} #{s.domain} #{s.name}"
      end
      next
    end

    puts "Site #{args[:id]} #{site.domain} #{site.name}"
    puts "=" * 60
    puts "  archive_url: #{site.archive_url}"
    puts "  last_crawled_at: #{site.last_crawled_at}"
    puts "  subscriptions: #{site.subscriptions.count}"
    puts "  articles: #{site.articles.count}"
    puts "  title_suffix_pattern: #{site.title_suffix_pattern}"
    puts "=" * 60

  end

  desc "Remove a site and all its subscriptions by site-id"
  task :remove, [ :site_id ] => :environment do |t, args|
    unless args[:site_id]
      puts "Usage:"
      puts "  bin/rake sites:remove[1]"
      puts "  bin/rails 'sites:remove[1]'  (for zsh)"
      puts "  bin/rails sites:remove\\[1\\]  (for zsh)"
      puts ""
      puts "Example:"
      puts "  bin/rake sites:remove[1]"
      next
    end

    site_id = args[:site_id]
    site = Website.find_by(id: site_id)

    unless site
      puts "ERROR: Site not found with id: #{site_id}"
      puts "\nAvailable sites:"
      Website.all.each do |s|
        puts "  - #{s.domain} (ID: #{s.id})"
      end
      next
    end

    # Show what will be deleted
    subscription_count = site.subscriptions.count
    article_count = site.articles.count

    puts "=" * 60
    puts "Site to be deleted:"
    puts "  Domain: #{site.domain}"
    puts "  Name: #{site.name || '(no name)'}"
    puts "  ID: #{site.id}"
    puts "  Subscriptions: #{subscription_count}"
    puts "  Articles: #{article_count}"
    puts "=" * 60

    # Confirm deletion only on production
    if Rails.env.production?
      print "\nWARNING: Are you sure you want to delete this site? (y/N): "
      confirmation = STDIN.gets.chomp.downcase

      unless confirmation == "y"
        puts "Deletion cancelled."
        next
      end
    end

    # Delete the site (subscriptions and articles will be deleted automatically due to dependent: :destroy)
    begin
      site.destroy
      puts "\nSuccessfully deleted site: #{site.domain}"
      puts "   - Removed #{subscription_count} subscription(s)"
      puts "   - Removed #{article_count} article(s)"
    rescue StandardError => e
      puts "\nERROR: Error deleting site: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end

  desc "Remove a subscription by user and site"
  task :remove_sub, [ :user_id, :site_id ] => :environment do |t, args|
    unless args[:user_id] && args[:site_id]
      puts "Usage:"
      puts "  bin/rake sites:remove_sub[1,2]"
      puts "  bin/rails 'sites:remove_sub[1,2]'  (for zsh)"
      puts "  bin/rails sites:remove_sub\\[1,2\\]  (for zsh)"
      puts ""
      puts "Example:"
      puts "  bin/rake sites:remove_sub[1,2]"
      next
    end
    user_id = args[:user_id]
    site_id = args[:site_id]
    subscription = Subscription.find_by(user_id: user_id, site_id: site_id)
    unless subscription
      puts "ERROR: Subscription not found with user_id: #{user_id} and site_id: #{site_id}"
      next
    end
    subscription.destroy
    puts "Successfully removed subscription: #{user_id} → #{site_id}"
  end
end
