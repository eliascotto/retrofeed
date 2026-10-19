# Article Extraction Architecture

This document describes the article content extraction system, its implementation, and potential performance improvements.

## Overview

The extraction system is responsible for extracting clean article content (HTML and Markdown) from web pages. It uses [Defuddle](https://github.com/kepano/defuddle) (a fork of Mozilla's Readability) running in Node.js.

Article content is fetched **only on demand, one article at a time**, via
`FetchArticleContentJob` (the "Download" button and the API refresh endpoint).
There is no automatic, whole-site content fetching: crawling a site only
discovers article records (title/url/date). The Node server's `/extract` endpoint
still accepts a batch (array) payload, but the Rails client no longer wraps it —
`ExtractorClient` only exposes single-article `extract`.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Rails Backend                                   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        Job Orchestration                             │    │
│  │                                                                      │    │
│  │  ┌────────────────────┐                                              │    │
│  │  │ Download button    │        ┌─────────────────────────────────┐  │    │
│  │  │ API refresh        │───────▶│ FetchArticleContentJob          │  │    │
│  │  │ (user-triggered)   │        │ (single article, on demand)     │  │    │
│  │  └────────────────────┘        │                                 │  │    │
│  │                                │ 1. Fetch article HTML           │  │    │
│  │                                │ 2. Extract content              │  │    │
│  │                                │ 3. Update article record        │  │    │
│  │                                └──────────────┬──────────────────┘  │    │
│  └───────────────────────────────────────────────┼──────────────────────┘    │
│                                                  │                           │
│  ┌────────────────────────────┐                  │                           │
│  │      ExtractorClient       │◀─────────────────┘                           │
│  │   (HTTP + Connection Pool) │                                              │
│  │   - extract(url, html)     │                                              │
│  └─────────────┬──────────────┘                                              │
│                │                                                             │
└────────────────┼─────────────────────────────────────────────────────────────┘
                 │
        Persistent HTTP Connection (keep-alive)
                 │
                 ▼
┌──────────────────────────────┐
│      Extractor Server        │
│      (Node.js HTTP)          │
│                              │
│  ┌────────────────────────┐  │
│  │  POST /extract         │  │
│  │  - Single item         │  │
│  │  - Batch processing    │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │  GET /health           │  │
│  │  - Server status       │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │  Defuddle + linkedom   │  │
│  │  - HTML parsing        │  │
│  │  - Content extraction  │  │
│  │  - Markdown conversion │  │
│  └────────────────────────┘  │
│                              │
│  Port: 3880 (EXTRACTOR_PORT) │
└──────────────────────────────┘
```

## Components

### 1. FetchArticleContentJob (Rails) - the only content fetcher

- Location: `app/jobs/fetch_article_content_job.rb`
- Queue: `content_fetcher` (SolidQueue)
- Responsibility: Fetch and extract a single article's content, on demand
- Process:
  1. Fetches HTML via `WebFetcher`
  2. Computes content hash for change detection
  3. Calls `WebProcessor.extract_article_content` with pre-fetched HTML
  4. Updates article record with extracted content

**When Used:**
- The "Download" button (`Articles::DownloadsController#create`)
- API refresh endpoint (`Api::ArticlesController#refresh`)

Both gate on `WebProcessor.should_update_content?(article, force: true)` for rate
limiting. Content is never fetched automatically for a whole site.

### 2. WebProcessor (Rails)

- Location: `app/services/web_processor.rb`
- Method: `extract_article_content(url, html: nil)`
- Responsibility: Interface between Rails and Node.js extractor
- Uses `ExtractorClient` for HTTP communication

### 3. ExtractorClient (Rails)

- Location: `app/services/extractor_client.rb`
- Responsibility: HTTP client with connection pooling for extractor server
- Features:
  - Persistent HTTP connections (keep-alive)
  - Automatic reconnection on connection loss
  - Thread-safe connection management
  - Configurable timeouts
  - Single-article extraction (`extract`)

### 4. Extractor Server (Node.js)

- Location: `node_scripts/extractor.js`
- Port: 3880 (configurable via `EXTRACTOR_PORT`)
- Dependencies: defuddle, linkedom
- Endpoints:
  - `POST /extract` - Extract content from URL or HTML (single or batch)
  - `GET /health` - Health check with uptime and memory stats

## On-Demand Content Flow

```
┌─────────────────────────────────────────┐
│ User clicks "Download" on one article    │
│ (or hits the API refresh endpoint)       │
└────────┬────────────────────────────────┘
         │ should_update_content?(force: true)  (rate limit)
         ▼
┌─────────────────────────────────────────┐
│ FetchArticleContentJob (single article) │
│                                         │
│ 1. Fetch article HTML via WebFetcher    │
│    (enforces robots.txt)                │
│                                         │
│ 2. Extract content                      │
│    WebProcessor.extract_article_content │
│    -> ExtractorClient.extract           │
│                                         │
│ 3. Update article record                │
│    - Content hash comparison            │
│    - Fill content_html/content_md/etc.  │
└─────────────────────────────────────────┘
```

## ExtractorClient API

```ruby
# Single extraction
result = ExtractorClient.extract(url: "https://example.com/article")
result = ExtractorClient.extract(url: "https://example.com", html: "<html>...")

# Health check
ExtractorClient.health
# => { status: "ok", uptime: 123.45, memory: {...} }

# Availability check
ExtractorClient.available?
# => true/false

# Reset connection (for testing or config changes)
ExtractorClient.reset_connection!
```

## Performance

### Per-article processing (FetchArticleContentJob)

| Operation | Time |
|-----------|------|
| HTTP request (pooled) | ~1-5ms |
| HTML parsing (linkedom) | ~20-50ms |
| Defuddle extraction | ~50-100ms |
| Markdown conversion | ~10-30ms |
| **Total per article** | **~80-200ms** |

## Error Handling

### ExtractorClient Errors

```ruby
begin
  result = ExtractorClient.extract(url: url, html: html)
rescue ExtractorClient::ConnectionError => e
  # Server not running or unreachable
rescue ExtractorClient::TimeoutError => e
  # Request or connection timeout
rescue ExtractorClient::ExtractorError => e
  # Other extraction errors
end
```

### Job Error Handling

```ruby
# FetchArticleContentJob handles errors per-article:

# Permanent errors (404, 403, 410, etc.)
# - Article marked as fetched (last_content_fetched_at updated)
# - Error recorded via ErrorReporter
# - No retry

# Transient errors (429, 5xx, network issues)
# - Error recorded via ErrorReporter
# - Article NOT marked as fetched
# - Will be retried via the job retry mechanism
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `EXTRACTOR_HOST` | localhost | Host of the extractor server |
| `EXTRACTOR_PORT` | 3880 | Port for extractor HTTP server |

### Timeouts (in ExtractorClient)

| Setting | Value | Description |
|---------|-------|-------------|
| `OPEN_TIMEOUT` | 5s | TCP connection timeout |
| `REQUEST_TIMEOUT` | 30s | HTTP request timeout |
| `keep_alive_timeout` | 30s | Keep-alive connection timeout |

### Procfile.dev

```
web: bin/rails server -b 0.0.0.0
css: bin/rails tailwindcss:watch
jobs: bin/jobs
node: npx nodemon --watch node_scripts --ext js,ts node node_scripts/extractor.js
```

## Monitoring

### Health Check

```bash
curl http://localhost:3880/health
# {"status":"ok","uptime":123.45,"memory":{"rss":...,"heapTotal":...}}
```

### From Rails Console

```ruby
ExtractorClient.health
# => {:status=>"ok", :uptime=>123.45, :memory=>{...}}

ExtractorClient.available?
# => true
```

## Testing

### Manual Testing

```bash
# Single extraction
curl -X POST http://localhost:3880/extract \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/article"}'

# Batch extraction
curl -X POST http://localhost:3880/extract \
  -H "Content-Type: application/json" \
  -d '[{"url":"https://example.com/a1"},{"url":"https://example.com/a2"}]'

# With pre-fetched HTML
curl -X POST http://localhost:3880/extract \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com","html":"<html>...</html>"}'

# Health check
curl http://localhost:3880/health
```

### Rails Console Testing

```ruby
# Test single extraction
result = ExtractorClient.extract(url: "https://overreacted.io/a-chain-reaction/")
puts result[:title]
puts result[:wordCount]

# Test with HTML
html = WebFetcher.fetch("https://example.com/article")
result = ExtractorClient.extract(url: "https://example.com/article", html: html)
```

### Test Files

- `test/jobs/fetch_article_content_job_test.rb` - Single-article fetch job tests
- `test/services/extractor_client_test.rb` - ExtractorClient tests
- `test/integration/crawling_pipeline_test.rb` - Full pipeline integration tests

## Future Improvements

### Alternative Approaches

| Approach | Pros | Cons |
|----------|------|------|
| Unix Sockets | ~10% faster than TCP | Unix-only, more complex |
| Ruby Readability | No IPC, simpler deploy | Different quality, no Markdown |
| MiniRacer (V8) | Near-zero IPC | Complex bundling, debugging |

### Potential Optimizations

- **Parallel HTML fetching**: Currently sequential per domain (for robots.txt compliance), could parallelize across domains
- **Streaming batch updates**: Update articles as they complete rather than waiting for full batch
- **Dynamic batch sizing**: Adjust batch size based on article size or domain characteristics

## See Also

- [Crawling Pipeline](./crawling_pipeline.md) - Full pipeline architecture
- [Defuddle](https://github.com/kepano/defuddle) - Content extraction library
