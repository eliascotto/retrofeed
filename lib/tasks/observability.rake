namespace :observability do
  # Module for observability tasks
  module ObservabilityTasks
    # Silence SQL logging
    def self.silence_sql
      logger = ActiveRecord::Base.logger
      return yield unless logger

      original_level = logger.level
      logger.level = Logger::WARN
      yield
    ensure
      logger.level = original_level if logger
    end

    # Print a section header
    def self.section(title)
      puts "\n#{title}"
      puts "-" * 80
    end

    # Safely print a value
    def self.safe(value)
      value.present? ? value : "(nil)"
    end
  end

  namespace :errors do
    desc "Print summary of recent errors (default: last 30 days) [usage: bin/rails 'observability:errors:summary[30]']"
    task :summary, [ :days ] => :environment do |_, args|
      days = (args[:days] || 30).to_i
      scope = ContentErrorGroup.where("last_seen_at >= ?", days.days.ago)

      ObservabilityTasks.silence_sql do
        puts "Error summary (last #{days} day(s))"
        puts "-" * 80

        ObservabilityTasks.section("By phase/operation/status")
        grouped = scope.group(:phase, :operation, :status).count
        if grouped.empty?
          puts "  none found"
        else
          puts format("  %-10s %-28s %-10s %6s", "Phase", "Operation", "Status", "Count")
          grouped.each do |(phase, op, status), count|
            puts format("  %-10s %-28s %-10s %6d", ObservabilityTasks.safe(phase), ObservabilityTasks.safe(op), ObservabilityTasks.safe(status), count)
          end
        end

        ObservabilityTasks.section("Top domains")
        domains = scope.group(:domain).order(Arel.sql("count_all DESC")).limit(10).count
        if domains.empty?
          puts "  none found"
        else
          domains.each_with_index do |(domain, count), idx|
            puts format("  %2d. %-40s %6d", idx + 1, ObservabilityTasks.safe(domain), count)
          end
        end

        ObservabilityTasks.section("Top subjects")
        subjects = scope.group(:subject_type, :subject_id).order(Arel.sql("count_all DESC")).limit(10).count
        if subjects.empty?
          puts "  none found"
        else
          subjects.each_with_index do |((stype, sid), count), idx|
            label = "#{ObservabilityTasks.safe(stype)}##{ObservabilityTasks.safe(sid)}"
            puts format("  %2d. %-36s %6d", idx + 1, label, count)
          end
        end

        latest = scope.order(last_seen_at: :desc).limit(5)
        ObservabilityTasks.section("Latest errors")
        if latest.empty?
          puts "  none found"
        else
          latest.each do |err|
            puts format("  [%-4d] %s (%3dx) %-10s %-26s %-10s", err.id, err.last_seen_at.utc.iso8601, err.occurrences_count, ObservabilityTasks.safe(err.phase), ObservabilityTasks.safe(err.operation), ObservabilityTasks.safe(err.status))
            puts "        subject=#{ObservabilityTasks.safe(err.subject_type)}##{ObservabilityTasks.safe(err.subject_id)} domain=#{ObservabilityTasks.safe(err.domain)}"
            puts "        url=#{ObservabilityTasks.safe(err.url)}"
            puts "        #{ObservabilityTasks.safe(err.message)}"
          end
        end
      end
    end

    desc "List latest open errors [usage: bin/rails 'observability:errors:open[20]']"
    task :open, [ :limit ] => :environment do |_, args|
      limit = (args[:limit] || 20).to_i
      scope = ContentErrorGroup.where(status: "open").order(last_seen_at: :desc).limit(limit)

      puts "Open errors (limit #{limit})"
      puts "-" * 80
      scope.each do |err|
        puts "  [#{err.id}] #{err.last_seen_at.utc.iso8601} (#{err.occurrences_count}x) #{err.phase}/#{err.operation}"
        puts "      subject=#{err.subject_type}##{err.subject_id} domain=#{err.domain} url=#{err.url}"
        puts "      #{err.message}"
      end
    end

    desc "Show errors for a website by id or domain [usage: bin/rails 'observability:errors:site[123]']"
    task :site, [ :website_ref ] => :environment do |_, args|
      ref = args[:website_ref]
      if ref.blank?
        puts "Provide website id or domain"
        next
      end

      ObservabilityTasks.silence_sql do
        website = Website.find_by(id: ref) || Website.find_by(domain: ref)
        unless website
          puts "Website not found for: #{ref}"
          next
        end

        scope = ContentErrorGroup.where(
          "(subject_type = ? AND subject_id = ?) OR domain = ?",
          "Website",
          website.id,
          website.domain
        ).where(status: "open").order(last_seen_at: :desc)

        puts "Website #{website.id} #{website.domain} (#{website.name})"
        puts "  archive_url: #{website.archive_url}"
        puts "  last_crawled_at: #{website.last_crawled_at}"
        puts "  articles: #{website.articles.count}"
        puts "-" * 80

        scope.each do |err|
          puts "  [#{err.id}] #{err.last_seen_at.utc.iso8601} (#{err.occurrences_count}x) #{err.phase}/#{err.operation}"
          puts "      url=#{err.url}"
          puts "      #{err.message}"
        end
      end
    end

    desc "Show errors for an article by id or url [usage: bin/rails 'observability:errors:article[123]']"
    task :article, [ :article_ref ] => :environment do |_, args|
      ref = args[:article_ref]
      if ref.blank?
        puts "Provide article id or url"
        next
      end

      ObservabilityTasks.silence_sql do
        article = Article.find_by(id: ref) || Article.find_by(url: ref)
        unless article
          puts "Article not found for: #{ref}"
          next
        end

        scope = ContentErrorGroup.where(
          subject: article
        ).where(status: "open").order(last_seen_at: :desc)

        puts "Article #{article.id} #{article.url}"
        puts "  title: #{article.title}"
        puts "  last_content_fetched_at: #{article.last_content_fetched_at}"
        puts "  has_content: #{article.content_html.present? || article.content_md.present?}"
        puts "-" * 80

        scope.each do |err|
          puts "  [#{err.id}] #{err.last_seen_at.utc.iso8601} (#{err.occurrences_count}x) #{err.phase}/#{err.operation}"
          puts "      url=#{err.url}"
          puts "      #{err.message}"
        end
      end
    end

    desc "Show errors associated to an ActiveJob id [usage: bin/rails 'observability:errors:job[abcd]']"
    task :job, [ :job_id ] => :environment do |_, args|
      job_id = args[:job_id]
      if job_id.blank?
        puts "Provide active_job_id"
        next
      end

      ObservabilityTasks.silence_sql do
        scope = ContentErrorGroup.where(active_job_id: job_id).order(last_seen_at: :desc)
        if scope.empty?
          puts "No errors found for job #{job_id}"
          next
        end

        puts "Errors for job #{job_id}"
        puts "-" * 80
        scope.each do |err|
          puts "  [#{err.id}] #{err.last_seen_at.utc.iso8601} (#{err.occurrences_count}x) #{err.phase}/#{err.operation} #{err.status}"
          puts "      subject=#{err.subject_type}##{err.subject_id} domain=#{err.domain} url=#{err.url}"
          puts "      #{err.message}"
        end
      end
    end

    desc "Show full details for an error id [usage: bin/rails 'observability:errors:show[1]']"
    task :show, [ :id ] => :environment do |_, args|
      id = args[:id]
      if id.blank?
        puts "Provide error id"
        next
      end

      ObservabilityTasks.silence_sql do
        err = ContentErrorGroup.find_by(id: id)
        unless err
          puts "Error group not found for id #{id}"
          next
        end

        puts "Error ##{err.id}"
        puts "-" * 80
        puts "phase/operation: #{err.phase}/#{err.operation}"
        puts "status/severity: #{err.status}/#{err.severity}"
        puts "subject: #{err.subject_type}##{err.subject_id}"
        puts "domain/url: #{err.domain} / #{err.url}"
        puts "message: #{err.message}"
        puts "exception_class: #{err.exception_class}"
        puts "occurrences: #{err.occurrences_count}"
        puts "first_seen_at: #{err.first_seen_at}"
        puts "last_seen_at: #{err.last_seen_at}"
        puts "job_class: #{err.job_class}"
        puts "active_job_id: #{err.active_job_id}"
        puts "queue_name: #{err.queue_name}"
        puts "attempt: #{err.attempt}"
        puts "job_arguments: #{err.job_arguments&.to_json}"
        puts "http_status: #{err.http_status}"
        puts "http_method: #{err.http_method}"
        puts "content_type: #{err.content_type}"
        puts "response_headers: #{err.response_headers&.to_json}"
        puts "created_at/updated_at: #{err.created_at} / #{err.updated_at}"
      end
    end

    desc "Resolve an error id (status=resolved) [usage: bin/rails 'observability:errors:resolve[1]']"
    task :resolve, [ :id ] => :environment do |_, args|
      id = args[:id]
      if id.blank?
        puts "Provide error id"
        next
      end

      ObservabilityTasks.silence_sql do
        err = ContentErrorGroup.find_by(id: id)
        unless err
          puts "Error group not found for id #{id}"
          next
        end

        err.update!(status: "resolved")
        puts "Resolved error ##{id}"
      end
    end
  end
end
