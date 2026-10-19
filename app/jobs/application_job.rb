class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  around_perform do |job, block|
    if Rails.logger.respond_to?(:tagged)
      Rails.logger.tagged(job.class.name, "job_id=#{job.job_id}") do
        perform_with_exception_logging(job, block)
      end
    else
      perform_with_exception_logging(job, block)
    end
  end

  private
    def perform_with_exception_logging(job, block)
      block.call
    rescue StandardError => e
      Rails.logger.error("[JobError] #{job.class.name} failed: #{e.class.name} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

      # Rails 7+ error reporting hook (if configured)
      if Rails.respond_to?(:error) && Rails.error
        Rails.error.report(
          e,
          handled: false,
          context: {
            job_class: job.class.name,
            job_id: job.job_id,
            queue_name: job.queue_name,
            arguments: (job.respond_to?(:arguments) ? job.arguments : nil)
          }.compact
        )
      end

      raise
    end
end
