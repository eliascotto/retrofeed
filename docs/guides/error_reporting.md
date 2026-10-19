# Error Reporting System

The error reporting system captures operational failures — broken feeds, failed fetches, unparseable content — in a queryable, deduplicated store. It is not a replacement for application exception tracking; it is domain-level observability for the content pipeline.

Three pieces compose it:

- **`ContentErrorGroup`** — the ActiveRecord model that persists errors to the database
- **`ErrorReporter`** — the service module that fingerprints and upserts error records
- **`ErrorReportable`** — the job concern that wraps `ErrorReporter` with job-specific convenience

## How errors are stored

Each unique error maps to one `content_error_groups` row, identified by a deterministic SHA256 fingerprint built from `phase + operation + exception_class + message + domain + subject`. When the same error recurs, the existing row is updated: `occurrences_count` increments and `last_seen_at` advances. A new row is only created when the fingerprint has not been seen before.

This means a broken website that fails 1000 article fetches produces one record with `occurrences_count: 1000`, not 1000 separate rows.

Each record carries:

| Field | Purpose |
|---|---|
| `fingerprint` | Deduplication key |
| `phase` | Stage of processing: `fetch`, `process`, `validate`, `job` |
| `operation` | Specific step that failed, e.g. `parse_date`, `retries_exhausted` |
| `subject` | Polymorphic reference to the Article or Website being processed |
| `domain` | Hostname, derived from subject or URL |
| `status` | `open`, `resolved`, or `ignored` |
| `severity` | `warn` or `error` |
| `occurrences_count` | How many times this error has fired |
| `first_seen_at` / `last_seen_at` | When it started and when it last recurred |
| `exception_class`, `message` | What went wrong |
| `job_class`, `active_job_id`, `attempt` | Which job was running |
| `http_status`, `http_method`, `response_headers` | HTTP context when relevant |

## Reporting errors from a job

Include `ErrorReportable` in any job that processes content. Then call the appropriate method from a `rescue` block or a `retry_on` callback.

```ruby
class FetchArticleContentJob < ApplicationJob
  include ErrorReportable

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.report_retries_exhausted(error)
  end

  def perform(article_id)
    @article = Article.find(article_id)
    @error_reporting_subject = @article   # tells ErrorReportable what was being processed

    fetch_content
  rescue ParseError => e
    report_error(e, phase: "process", operation: "parse_content")
    raise
  end
end
```

Set `@error_reporting_subject` at the top of `perform` so all reporting methods can resolve the subject automatically without passing it on every call.

### Available methods

**`report_error(exception, phase:, operation:, **opts)`**

Reports a single error mid-execution. Re-raise the exception afterward if the job should still retry.

```ruby
rescue DateExtractionError => e
  report_error(e, phase: "process", operation: "extract_date")
  raise
end
```

Optional keyword arguments:
- `subject:` — overrides `@error_reporting_subject`
- `severity:` — `"warn"` or `"error"` (default: `"error"`)
- Any extra key-value pairs are forwarded to the record.

**`report_retries_exhausted(error)`**

Designed for `retry_on` callbacks. Records a terminal failure with `phase: "job"` and `operation: "retries_exhausted"`. The subject is inferred from job arguments when not set explicitly.

```ruby
retry_on Net::ReadTimeout, attempts: 5 do |job, error|
  job.report_retries_exhausted(error)
end
```

**`report_batch_error(error, article_ids:, phase:, operation:)`**

For jobs that process arrays of articles. Groups the error by website to avoid per-article spam, and marks all affected articles as `content_fetch_failed_at`.

```ruby
rescue StandardError => e
  report_batch_error(e, article_ids: article_ids, phase: "fetch", operation: "batch_request")
  raise
end
```

## Reporting errors outside jobs

Call `ErrorReporter.record` directly from controllers, services, or models. Pass all context explicitly since there is no job object to infer from.

```ruby
ErrorReporter.record(
  subject: website,
  phase: "process",
  operation: "feed_parse",
  message: e.message,
  exception: e,
  domain: website.domain,
  severity: "error"
)
```

`ErrorReporter.record` swallows its own exceptions — a failure inside the reporter will log to `Rails.logger` but will not propagate, so it is safe to call without an outer rescue.

## Choosing phase and operation

Use consistent values so fingerprints collapse correctly across jobs.

| Phase | When |
|---|---|
| `fetch` | Making an HTTP request |
| `process` | Parsing, extracting, or transforming content |
| `validate` | Checking data integrity before saving |
| `job` | Job lifecycle events (retry exhaustion, unexpected failure) |

`operation` should be a short snake_case label for the specific step: `parse_date`, `extract_content`, `retries_exhausted`, `feed_request`.

## Querying errors

See [observability.md](../observability.md) for the rake tasks that query, detail, and resolve error groups.
