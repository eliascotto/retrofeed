# Concern for jobs that need to report errors to ContentErrorGroup via ErrorReporter.
#
# This provides helper methods and callbacks for consistent error reporting across
# content-related jobs. It ensures that all failures (including retry exhaustion
# and unexpected errors) are captured in content_error_groups for observability.
#
# Usage:
#   class MyJob < ApplicationJob
#     include ErrorReportable
#
#     # Report errors when retries are exhausted
#     retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
#       job.report_retries_exhausted(error)
#     end
#
#     def perform(article_id)
#       @article = Article.find(article_id)
#       # ... processing logic ...
#     rescue SomeError => e
#       report_error(e, phase: "fetch", operation: "some_operation")
#       raise
#     end
#   end
#
module ErrorReportable
  extend ActiveSupport::Concern

  included do
    # Track the subject(s) being processed for error reporting
    attr_accessor :error_reporting_subject, :error_reporting_subjects
  end

  # Report an error to ErrorReporter with standard formatting
  #
  # @param exception [Exception] The exception that occurred
  # @param phase [String] The phase of processing ("fetch", "process", "validate")
  # @param operation [String] The specific operation that failed
  # @param subject [Object, nil] The subject (e.g., Article) - defaults to @error_reporting_subject
  # @param severity [String] Severity level (default: "error")
  # @param extra [Hash] Additional context to include
  def report_error(exception, phase:, operation:, subject: nil, severity: "error", **extra)
    subject ||= error_reporting_subject

    ErrorReporter.record(
      subject: subject,
      phase: phase,
      operation: operation,
      message: exception.message,
      exception: exception,
      url: extract_url_from_subject(subject),
      domain: extract_domain_from_subject(subject),
      job: self,
      severity: severity,
      http: extract_http_context(exception),
      **extra
    )
  end

  # Report when all retries have been exhausted for this job.
  # Call this from the retry_on block.
  #
  # @param error [Exception] The error that caused the final failure
  # @param subject [Object, nil] The subject - will try to infer from job arguments
  def report_retries_exhausted(error, subject: nil)
    subject ||= infer_subject_from_arguments

    ErrorReporter.record(
      subject: subject,
      phase: "job",
      operation: "retries_exhausted",
      message: "Job failed after #{executions} attempts: #{error.message}",
      exception: error,
      url: extract_url_from_subject(subject),
      domain: extract_domain_from_subject(subject),
      job: self,
      severity: "error"
    )
  end

  # Report a batch-level error affecting multiple articles
  #
  # @param error [Exception] The error that occurred
  # @param article_ids [Array<Integer>] The IDs of articles affected
  # @param phase [String] The phase of processing
  # @param operation [String] The operation that failed
  def report_batch_error(error, article_ids:, phase:, operation:)
    # For batch errors, we create one error group per website to avoid spam
    # but include article IDs in the message for traceability
    websites = Article.where(id: article_ids).includes(:website).map(&:website).uniq.compact

    # Mark all articles as failed to fetch content
    Article.where(id: article_ids).update_all(content_fetch_failed_at: Time.current)

    if websites.empty?
      # No website context - report as generic job error
      ErrorReporter.record(
        subject: nil,
        phase: phase,
        operation: operation,
        message: "Batch error for article_ids #{article_ids.first(5).join(', ')}...: #{error.message}",
        exception: error,
        job: self,
        severity: "error"
      )
    else
      # Report one error per website
      websites.each do |website|
        website_article_ids = Article.where(id: article_ids, website_id: website.id).pluck(:id)
        ErrorReporter.record(
          subject: website,
          phase: phase,
          operation: operation,
          message: "Batch error for #{website_article_ids.length} articles: #{error.message}",
          exception: error,
          domain: website.domain,
          job: self,
          severity: "error"
        )
      end
    end
  end

  private
    # Try to infer the subject from job arguments (for single-article jobs)
    def infer_subject_from_arguments
      return nil unless respond_to?(:arguments)

      first_arg = arguments.first
      case first_arg
      when Integer
        # Assume it's an article_id
        Article.find_by(id: first_arg)
      when Array
        # Batch job - return nil, use report_batch_error instead
        nil
      else
        nil
      end
    end

    def extract_url_from_subject(subject)
      return nil unless subject
      subject.try(:url) || subject.try(:archive_url)
    end

    def extract_domain_from_subject(subject)
      return nil unless subject
      subject.try(:domain) || subject.try(:website)&.try(:domain)
    end

    def extract_http_context(exception)
      return {} unless exception.respond_to?(:http_status)

      {
        http_status: exception.http_status,
        http_method: exception.try(:http_method) || "GET",
        content_type: exception.try(:content_type),
        headers: exception.try(:headers)
      }.compact
    end
end
