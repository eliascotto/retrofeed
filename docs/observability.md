# Observability Tasks

The `observability.rake` file provides a set of tasks for monitoring and managing content processing errors. These tasks help you understand what errors are occurring during the content fetching and processing pipeline.

## Error Summary

Get an overview of recent errors grouped by various dimensions:

```bash
bin/rails 'observability:errors:summary[30]'
```

This shows:
- Errors grouped by phase/operation/status
- Top domains with errors
- Top subjects (articles/websites) with errors
- Latest 5 errors with details

The default time period is 30 days if not specified.

## Listing Open Errors

View all currently open (unresolved) errors:

```bash
bin/rails 'observability:errors:open[20]'
```

Shows the latest 20 open errors by default. Adjust the limit as needed.

## Error Details by Context

### By Website

View errors for a specific website by ID or domain:

```bash
bin/rails 'observability:errors:site[example.com]'
bin/rails 'observability:errors:site[123]'
```

This displays website information and all open errors associated with that website.

### By Article

View errors for a specific article by ID or URL:

```bash
bin/rails 'observability:errors:article[456]'
bin/rails 'observability:errors:article[https://example.com/article]'
```

Shows article details and all open errors for that article.

### By Job

View errors associated with a specific ActiveJob:

```bash
bin/rails 'observability:errors:job[abcd-1234-efgh]'
```

Useful for debugging issues with a specific background job execution.

## Viewing Error Details

Get full details for a specific error:

```bash
bin/rails 'observability:errors:show[1]'
```

This displays all available information about the error including:
- Phase, operation, status, severity
- Subject (article/website) and domain/URL
- Exception details
- Occurrence count and timestamps
- Job information (class, ID, queue, attempt)
- HTTP details (status, method, content type, headers)

## Resolving Errors

Mark an error as resolved:

```bash
bin/rails 'observability:errors:resolve[1]'
```

This sets the error status to "resolved". Resolved errors are excluded from the `open` task results.

## Common Workflows

### Daily Error Review

```bash
# Get summary of last 7 days
bin/rails 'observability:errors:summary[7]'

# Review open errors
bin/rails 'observability:errors:open[50]'
```

### Investigating a Specific Issue

```bash
# Find errors for a problematic website
bin/rails 'observability:errors:site[example.com]'

# Get details on a specific error
bin/rails 'observability:errors:show[42]'

# Resolve after fixing
bin/rails 'observability:errors:resolve[42]'
```

### Debugging Failed Jobs

```bash
# Find errors from a specific job
bin/rails 'observability:errors:job[job-id-from-logs]'

# Get full details
bin/rails 'observability:errors:show[error-id]'
```
