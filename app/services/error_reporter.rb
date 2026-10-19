require "digest"

module ErrorReporter
  # Centralized utility for grouping and persisting operational errors with
  # consistent fingerprints so noisy repeats collapse into one record.
  module_function

  HEADER_ALLOWLIST = %w[content-type cache-control retry-after server].freeze
  DEFAULT_SEVERITY = "error"
  DEFAULT_STATUS = "open"

  # Upserts a ContentErrorGroup keyed by a deterministic fingerprint; increments
  # occurrences for existing groups and stores lightweight context about the
  # failing job/request.
  def record(subject: nil, phase:, operation:, message:, exception: nil, url: nil, domain: nil, job: nil, http: {}, severity: DEFAULT_SEVERITY, status: DEFAULT_STATUS)
    return if message.blank?

    normalized_message = safe_truncate(message.to_s.strip, 2000)
    domain ||= begin
      subject&.respond_to?(:domain) ? subject.domain : UrlUtils.extract_domain(url)
    rescue UrlUtils::InvalidUrlError
      nil
    end

    # Prefer explicit http hash; fall back to exception payload when present
    http_status = http[:http_status] || http[:status] || exception.try(:http_status)
    http_method = http[:http_method] || http[:method] || exception.try(:http_method)
    content_type = http[:content_type] || exception.try(:content_type)
    response_headers = http[:headers] || exception.try(:headers)

    fingerprint = build_fingerprint(
      phase: phase,
      operation: operation,
      exception_class: exception&.class&.name,
      message: normalized_message,
      domain: domain,
      url: url,
      subject: subject
    )

    now = Time.current

    attrs = {
      phase: phase,
      operation: operation,
      severity: severity || DEFAULT_SEVERITY,
      status: status || DEFAULT_STATUS,
      message: normalized_message,
      exception_class: exception&.class&.name,
      domain: domain,
      url: url,
      job_class: job&.class&.name,
      active_job_id: job.try(:job_id),
      queue_name: job.try(:queue_name),
      job_arguments: serialize_job_arguments(job),
      attempt: job.try(:executions),
      http_status: http_status,
      http_method: http_method,
      content_type: content_type,
      response_headers: allowlisted_headers(response_headers),
      last_seen_at: now
    }

    group = ContentErrorGroup.find_by(fingerprint: fingerprint, subject: subject, domain: domain)

    if group
      group.with_lock do
        group.assign_attributes(attrs.compact)
        group.occurrences_count = group.occurrences_count.to_i + 1
        group.save!
      end
    else
      ContentErrorGroup.create!(
        {
          fingerprint: fingerprint,
          subject: subject,
          first_seen_at: now,
          occurrences_count: 1
        }.merge(attrs.compact)
      )
    end
  rescue StandardError => e
    Rails.logger.error("[ErrorReporter] Failed to record error: #{e.class.name} - #{e.message}")
  end

  # Generates a deterministic hash so equivalent errors collapse even when
  # reported from different jobs/requests.
  def build_fingerprint(phase:, operation:, exception_class:, message:, domain:, url:, subject:)
    subject_key = if subject
      "#{subject.class.name}-#{subject.id}"
    else
      "none"
    end

    Digest::SHA256.hexdigest(
      [ phase, operation, exception_class || "Error", message&.truncate(200), domain, subject_key ].compact.join("|")
    )
  end

  # Strips job arguments down to safe, comparable identifiers to avoid logging
  # sensitive or verbose payloads.
  def serialize_job_arguments(job)
    return nil unless job&.respond_to?(:arguments)

    safe_args = Array(job.arguments).map do |arg|
      case arg
      when Hash
        arg.slice(:id, :website_id, :article_id, :user_id, :url)
      when Array
        arg.take(5)
      else
        arg
      end
    end

    safe_args
  rescue StandardError
    nil
  end

  # Keeps only safe headers for storage to reduce PII risk and storage bloat.
  def allowlisted_headers(headers)
    return nil unless headers.respond_to?(:to_h)

    headers.to_h
          .transform_keys { |k| k.to_s.downcase }
          .slice(*HEADER_ALLOWLIST)
  rescue StandardError
    nil
  end

  def safe_truncate(text, max)
    return text if text.blank? || text.length <= max

    "#{text[0, max]}…"
  end
end
