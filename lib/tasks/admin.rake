namespace :admin do
  task reset_db: :environment do
    Rake::Task["db:drop"].invoke
    Rake::Task["db:reset"].invoke
  end

  desc "Fix stuck websites by finalising their processing status"
  task fix_stuck_websites: :environment do
    puts "=== Finding stuck websites ==="

    # Find websites stuck in extracting/crawling for more than 30 minutes.
    # Content is fetched only on demand per article, so a stuck crawl just needs
    # its status finalised rather than any content jobs re-enqueued.
    stuck = Website.where(processing_status: %w[extracting crawling])
                   .where("processing_started_at < ?", 30.minutes.ago)

    if stuck.empty?
      puts "No stuck websites found."
      next
    end

    puts "Found #{stuck.count} stuck websites:"
    stuck.each do |w|
      puts "  - #{w.domain} (#{w.processing_status} since #{w.processing_started_at})"
    end

    puts ""
    puts "=== Marking stuck websites as completed ==="

    stuck.each do |website|
      website.update!(
        processing_status: "completed",
        processing_error_message: nil,
        processing_failed_at: nil
      )
      puts "#{website.domain}: marked as completed"
    end

    puts ""
    puts "Done! Check status with: rake diagnose:stuck"
  end

  desc "Clear all failed SolidQueue jobs"
  task clear_failed_jobs: :environment do
    failed = SolidQueue::FailedExecution.count
    if failed == 0
      puts "No failed jobs to clear."
      next
    end

    puts "Clearing #{failed} failed jobs..."
    SolidQueue::FailedExecution.find_each do |fe|
      fe.job.destroy
    end
    puts "Done."
  end

  desc "Show SolidQueue job statistics"
  task job_stats: :environment do
    puts "=== SolidQueue Job Statistics ==="
    puts ""

    # Pending jobs by class
    pending = SolidQueue::Job.where(finished_at: nil)
                             .where.not(id: SolidQueue::FailedExecution.select(:job_id))
                             .group(:class_name)
                             .count
    if pending.any?
      puts "Pending jobs:"
      pending.each { |cls, count| puts "  #{cls}: #{count}" }
    else
      puts "No pending jobs"
    end
    puts ""

    # Failed jobs by class
    failed = SolidQueue::FailedExecution
      .joins(:job)
      .group("solid_queue_jobs.class_name")
      .count
    if failed.any?
      puts "Failed jobs:"
      failed.each { |cls, count| puts "  #{cls}: #{count}" }

      # Show recent failure reasons
      puts ""
      puts "Recent failure reasons:"
      SolidQueue::FailedExecution.joins(:job).order(created_at: :desc).limit(5).each do |fe|
        error = fe.error
        msg = error.is_a?(Hash) ? error["message"] : error.to_s
        puts "  [#{fe.job.class_name}] #{msg.to_s.truncate(80)}"
      end
    else
      puts "No failed jobs"
    end
  end
end
