# Archive Page Detection

This document describes how retrofeed detects archive pages for new websites.

## Overview

An **archive page** is an index page that links to multiple blog posts. It's the primary mechanism for discovering a blog's content. When a user submits a URL, retrofeed needs to identify which page contains the list of posts to crawl.

Archive detection runs **only for new websites** (domains not yet in the database). For existing websites, the stored `archive_url` is used directly.

## Detection Algorithm

The `ArchivePageDetector` service evaluates candidate pages using multiple strategies in priority order:

### Strategy A: User-Provided URL Validation

First, check if the URL the user submitted is already a valid archive:

1. Fetch the page content
2. Validate with `WebProcessor.contains_valid_archive?`
3. If valid: `method=user_provided`, `confidence=1.0`

### Strategy B: Known Path Probing

Probe common archive paths under the site origin:

- `/archive`, `/archives`
- `/blog`, `/posts`, `/articles`
- `/writing`, `/essays`, `/notes`

For each path:
1. HEAD request to check existence (fast)
2. If 2xx response, GET and validate with `contains_valid_archive?`
3. If valid: `method=known_path`, `confidence=0.9`

### Strategy C: Link Analysis

Analyze the origin page for archive-like links:

1. Fetch the origin page
2. Check if origin itself is an archive (homepage with posts)
3. Find links in navigation with archive keywords (archive, blog, posts, etc.)
4. For each candidate, fetch and validate
5. Score candidates based on:
   - Link text keywords
   - URL path keywords
   - DOM structure (`<article>`, `.post`, `<time>` elements)
   - Presence of pagination

Best candidate: `method=link_analysis`, `confidence=0.5-0.85`

### Strategy D: Feed-Assisted Discovery

As a last resort, use RSS/Atom feeds:

1. Find feed links (`<link rel="alternate">`) or probe common paths (`/feed`, `/rss`, etc.)
2. Parse feed to extract post URLs
3. Check if origin links to multiple feed items
4. If yes: `method=feed_assisted`, `confidence=0.75`

## Validation Heuristic

A page is considered a valid archive when `WebProcessor.contains_valid_archive?` returns true. This checks for:

- Multiple internal links (5+ by default)
- Links following article-like patterns (not `/tag/`, `/category/`, etc.)
- Date-based URL patterns (`/YYYY/MM/DD/`)
- Grouped path patterns (e.g., multiple `/posts/2024/...` links)

## Pagination Detection

For any detected archive, pagination is checked by looking for:

- `rel="next"` or `rel="prev"` links
- `.pagination` containers or page number navigation
- Links matching `/page/\d+` or `?page=\d+`

When pagination is detected:
- The archive is still crawled (page 1 only)
- `archive_paginated=true` is persisted on the Website
- A warning is logged indicating pagination exists

Future paginator algorithm will handle crawling additional pages.

## Data Model

Detection metadata is stored on the `Website` model:

| Column | Type | Description |
|--------|------|-------------|
| `archive_url` | string | The detected/validated archive URL |
| `archive_detection_method` | string | How it was found: `user_provided`, `known_path`, `link_analysis`, `feed_assisted` |
| `archive_confidence_score` | float | Confidence from 0.0 to 1.0 |
| `archive_paginated` | boolean | Whether pagination was detected |

## Pipeline Integration

```
User submits URL
       |
       v
ProcessWebsiteJob
       |
       +-- Website exists? --YES--> Use stored archive_url
       |                            Pass existing metadata to CrawlArchiveJob
       |
       NO
       |
       v
ArchivePageDetector.detect(url)
       |
       +-- Returns Result(url, method, confidence, pagination)
       |
       v
CrawlArchiveJob(url, detection_metadata)
       |
       v
Persist Website with archive_url and detection metadata
```

## Testing

### Unit Tests

`test/services/archive_page_detector_test.rb` covers:

- Valid user-provided archive detection
- Known path fallback
- Homepage-as-archive detection
- Pagination detection (rel=next, page numbers, query params)
- Network error handling
- Detection failure cases

### Adding Test Fixtures

To test detection for a specific blog structure:

1. Add HTML fixture to `test/fixtures/websites/{site_name}/archive.html`
2. Update `test/fixtures/files/mock_mapping.yml` with domain mapping
3. Write test case stubbing the appropriate HTTP requests

### Stubbing HTTP

Tests use WebMock. Stub all potential requests:

```ruby
# Known paths
%w[/archive /archives /blog /posts /articles /writing /essays /notes].each do |path|
  stub_request(:head, "https://example.com#{path}").to_return(status: 404)
end

# Feed paths (for feed-assisted strategy)
%w[/feed /rss /rss.xml /atom.xml /feed.xml /index.xml].each do |path|
  stub_request(:head, "https://example.com#{path}").to_return(status: 404)
end

# Origin and target pages
stub_request(:get, "https://example.com").to_return(body: html, status: 200)
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Single-page blog (all posts on homepage) | Detected via link_analysis (origin is archive) |
| No archive page at all | `DetectionError` raised, converted to `InvalidArchiveError` |
| Paginated archive | Crawl page 1, flag `archive_paginated=true` |
| Multiple archive candidates | Highest-scoring candidate selected |
| robots.txt blocks archive | Detection fails (respects robots.txt) |

## Limitations

- **JavaScript-rendered archives**: Not supported; detection uses static HTML only
- **Infinite scroll**: Detected as non-paginated (no page links)
- **Category/tag archives**: May be selected if they score highest; no distinction from main archive
- **Multi-author blogs**: Per-author archives not specifically handled

## Future Improvements

- Learning loop to track which detection methods work for specific blog platforms
- JavaScript rendering support via headless browser
- Pagination crawling (separate algorithm)




