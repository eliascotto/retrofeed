# Scraping Safety Measures

This document describes all safety measures implemented in Retrofeed's web scraping system to ensure respectful, safe, and trap-resistant scraping behavior.

## Overview

Retrofeed implements multiple layers of safety measures to:
1. **Respect robots.txt rules** - Honor site owners' crawling preferences
2. **Avoid AI traps and bot detection** - Prevent falling into honeypots and traps
3. **Prevent infinite loops** - Detect and halt circular pagination
4. **Enforce rate limiting** - Use random delays to avoid predictable patterns
5. **Set hard limits** - Prevent runaway jobs from consuming excessive resources

## Table of Contents

- [Robots.txt Compliance](#robotstxt-compliance)
- [Random Delays and Jitter](#random-delays-and-jitter)
- [AI Trap Detection](#ai-trap-detection)
- [Hard Limits](#hard-limits)
- [Implementation Details](#implementation-details)

---

## Robots.txt Compliance

### Implementation

The `RobotsTxt` service (`app/services/robots_txt.rb`) handles all robots.txt compliance:

1. **Fetches robots.txt** from domain root before scraping
2. **Caches parsed rules** per domain (24-hour TTL) for efficiency
3. **Respects User-agent specific rules** (falls back to "*" if no specific match)
4. **Enforces path matching** with longest-match-wins logic
5. **Handles Allow/Disallow rules** (Allow overrides Disallow for equal specificity)
6. **Enforces crawl-delay** between requests with random jitter
7. **Fails open** (allows scraping) if robots.txt is missing or inaccessible

### Usage

All HTTP requests go through `WebFetcher::Live.fetch()`, which automatically:
- Checks if the path is allowed by robots.txt
- Enforces crawl-delay with random jitter before each request
- Raises `WebFetcher::FetchError` if robots.txt disallows the path

```ruby
# Automatic enforcement in WebFetcher::Live
html = WebFetcher.fetch("https://example.com/archive")
# ↑ Automatically checks robots.txt and enforces crawl-delay
```

### Key Features

- **User-agent aware**: Checks rules for specific user-agent (default: "retrofeed")
- **Path matching**: Uses longest-prefix matching for rule specificity
- **Caching**: 24-hour cache per domain to avoid repeated fetches
- **Fail-open policy**: If robots.txt is unavailable, scraping proceeds (assumes allowed)

---

## Random Delays and Jitter

### Purpose

Random delays serve multiple safety purposes:
1. **Respect robots.txt crawl-delay** - Honor site owner's rate limiting preferences
2. **Avoid predictable patterns** - Make request timing less regular and more human-like
3. **Prevent bot detection** - Anti-bot systems often detect perfectly regular intervals
4. **Reduce server load** - Spread requests over time to avoid overwhelming servers

### Implementation

#### Ruby Scraper (Main Application)

**Location**: `app/services/robots_txt.rb`

The `enforce_crawl_delay_with()` method adds random jitter to crawl delays:

```ruby
# Base delay from robots.txt (or default 1.0s)
base_delay = robots&.crawl_delay(user_agent) || DEFAULT_CRAWL_DELAY

# Add random jitter (0-30% of base delay)
jitter_multiplier = 1.0 + rand(CRAWL_DELAY_JITTER_RANGE)  # 0.0..0.3
delay = base_delay * jitter_multiplier
```

**Jitter Range**: 0% to 30% of the base delay
- If robots.txt specifies `Crawl-delay: 5`, actual delay will be 5.0s to 6.5s (random)
- If no crawl-delay specified, default is 1.0s, so delay will be 1.0s to 1.3s (random)

**Example**:
- Base delay: 2.0 seconds
- Jitter: 0% to 30% (random)
- Actual delay: 2.0s to 2.6s (randomly chosen each time)

#### Node.js Scraper

**Location**: `tools/scraper/src/env.js`

The Node.js scraper uses configurable random delays:

```javascript
// Random delay between REQUEST_DELAY_MIN and REQUEST_DELAY_MAX
export function getRequestDelay() {
  const min = parseInt(process.env.REQUEST_DELAY_MIN, 10) || 500;
  const max = parseInt(process.env.REQUEST_DELAY_MAX, 10) || 3000;
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
```

**Default Range**: 500ms to 3000ms (configurable via environment variables)

**Configuration**:
- `REQUEST_DELAY_MIN`: Minimum delay in milliseconds (default: 500)
- `REQUEST_DELAY_MAX`: Maximum delay in milliseconds (default: 3000)

### Why Randomization Matters

1. **Bot Detection Avoidance**: Many anti-bot systems monitor for:
   - Exact timing intervals (e.g., exactly 1.0s between requests)
   - Perfectly regular request patterns
   - Non-human behavior patterns

2. **Human-like Behavior**: Real users don't make requests at perfectly regular intervals. Randomization makes scraping behavior more natural.

3. **Trap Avoidance**: Some AI traps are triggered by detecting regular patterns. Random delays help avoid these triggers.

---

## AI Trap Detection

### Overview

The `PaginationGuard` class (`app/services/pagination_guard.rb`) implements multiple trap detection mechanisms to prevent the scraper from falling into infinite loops or bot traps.

### Detection Mechanisms

#### 1. Circular URL Detection

**What it detects**: Same URL appearing multiple times in pagination

**Why it matters**: Prevents infinite loops where pagination links cycle back to earlier pages

**Implementation**:
```ruby
if @seen_urls.include?(page_url)
  halt!(:circular_url, "Already visited: #{page_url}")
  return false
end
```

**Threshold**: Any URL revisit immediately halts pagination

#### 2. Page Number Jump Detection

**What it detects**: Sudden jumps in page numbers (e.g., page 5 → page 999999)

**Why it matters**: Bot traps often generate fake high-numbered pages to waste scraper resources

**Implementation**:
```ruby
if page_number && @last_page_number > 0
  jump = page_number - @last_page_number
  if jump > @max_page_jump  # Default: 100
    halt!(:page_jump, "Jump exceeds max")
    return false
  end
end
```

**Threshold**: Default max jump is 100 pages (configurable via `Website::PAGINATION_MAX_PAGE_JUMP`)

#### 3. Content Fingerprint Detection

**What it detects**: Identical content appearing on different URLs

**Why it matters**: Honeypot pages often serve the same content with different URLs to waste scraper time

**Implementation**:
```ruby
fingerprint = PaginationGuard.generate_fingerprint(page_url, post_urls)
if @content_fingerprints.include?(fingerprint)
  halt!(:duplicate_content, "Content fingerprint already seen")
  return false
end
```

**Fingerprint Method**: SHA256 hash of page URL + sorted list of post URLs found on that page

**Why this approach**: More stable than hashing full HTML (which can vary due to ads, timestamps, etc.)

#### 4. Empty Page Detection

**What it detects**: Consecutive pages with no posts

**Why it matters**: Indicates we've reached the end of content or hit a trap serving empty pages

**Implementation**:
```ruby
if discovered_posts.empty?
  @consecutive_empty += 1
  if @consecutive_empty >= @max_consecutive_empty  # Default: 3
    halt!(:empty_pages, "#{@consecutive_empty} consecutive empty pages")
    return false
  end
end
```

**Threshold**: Default is 3 consecutive empty pages (configurable via `Website::PAGINATION_MAX_CONSECUTIVE_EMPTY`)

#### 5. Duplicate Post Detection

**What it detects**: Pages that only contain posts we've already seen

**Why it matters**: Prevents circular pagination where the same posts repeat across pages

**Implementation**:
```ruby
new_posts = discovered_posts.reject { |url| @post_urls.include?(url) }
if new_posts.empty? && discovered_posts.any?
  @duplicate_post_streak += 1
  if @duplicate_post_streak >= @max_duplicate_streak  # Default: 10
    halt!(:circular_pagination, "Only duplicate posts")
    return false
  end
end
```

**Threshold**: Default is 10 consecutive pages with only duplicate posts (configurable via `Website::PAGINATION_MAX_DUPLICATE_STREAK`)

### Usage

The `PaginationGuard` is used in `PaginateArchiveJob`:

```ruby
guard = PaginationGuard.new
scraper.each_page do |page_number, page_url, html, articles_data|
  fingerprint = PaginationGuard.generate_fingerprint(page_url, post_urls)
  
  unless guard.safe_to_continue?(
    page_url: page_url,
    page_number: page_num_from_url,
    content_fingerprint: fingerprint,
    discovered_posts: post_urls
  )
    halt_pagination!(website, "trap_detected", guard.halt_subreason)
    break
  end
end
```

### Halt Reasons

When a trap is detected, pagination halts with one of these reasons:
- `:circular_url` - URL already visited
- `:page_jump` - Page number jump exceeds threshold
- `:duplicate_content` - Content fingerprint already seen
- `:empty_pages` - Too many consecutive empty pages
- `:circular_pagination` - Too many pages with only duplicate posts

---

## Hard Limits

### Purpose

Hard limits prevent runaway jobs from consuming excessive resources, even if trap detection fails.

### Limits

All limits are defined in `app/models/website.rb`:

| Limit | Value | Purpose |
|-------|-------|---------|
| `PAGINATION_MAX_PAGES` | 500 | Maximum pages to crawl per archive |
| `PAGINATION_MAX_POSTS` | 10,000 | Maximum posts to discover per archive |
| `PAGINATION_MAX_DURATION` | 30 minutes | Maximum time for pagination job |
| `PAGINATION_MAX_CONSECUTIVE_EMPTY` | 3 | Consecutive empty pages before halt |
| `PAGINATION_MAX_DUPLICATE_STREAK` | 10 | Consecutive pages with only duplicates |
| `PAGINATION_MAX_PAGE_JUMP` | 100 | Maximum page number jump allowed |

### Enforcement

Hard limits are checked in `PaginateArchiveJob`:

```ruby
# Duration limit
elapsed = Time.current - start_time
if elapsed > max_duration
  halt_pagination!(website, "duration_limit", "Exceeded #{max_duration.to_i}s")
  break
end

# Page limit
if page_number > page_limit
  halt_pagination!(website, "page_limit", "Exceeded #{page_limit} pages")
  break
end

# Post limit
if guard.total_posts_discovered > post_limit
  halt_pagination!(website, "post_limit", "Exceeded #{post_limit} posts")
  break
end
```

### Configurability

- **Per-site overrides**: Websites can have custom `pagination_page_limit` and `pagination_post_limit`
- **Environment variables**: Defaults can be set via:
  - `RETROFEED_PAGINATION_DEFAULT_PAGE_LIMIT`
  - `RETROFEED_PAGINATION_DEFAULT_POST_LIMIT`
  - `RETROFEED_PAGINATION_MAX_DURATION_SECONDS`
- **Hard caps**: All limits are capped by the hard maximums (cannot exceed 500 pages, 10,000 posts, 30 minutes)

---

## Implementation Details

### Request Flow

1. **Job starts** (`PaginateArchiveJob.perform`)
2. **Scraper initialized** (`PaginatedArchiveScraper.new`)
3. **For each page**:
   - **WebFetcher.fetch()** is called
     - Checks robots.txt (via `enforce_robots_if_needed`)
     - Enforces crawl-delay with jitter
     - Makes HTTP request
   - **Articles extracted** from HTML
   - **PaginationGuard checks** trap conditions
   - **Hard limits checked** (pages, posts, duration)
   - **Next page URL found** (or pagination ends)
4. **Job completes** or halts with reason

### Key Classes

#### `RobotsTxt` (`app/services/robots_txt.rb`)
- Fetches and parses robots.txt files
- Caches parsed rules per domain
- Enforces crawl-delay with random jitter
- Checks if paths are allowed

#### `PaginationGuard` (`app/services/pagination_guard.rb`)
- Tracks visited URLs, content fingerprints, post URLs
- Detects circular pagination, page jumps, duplicate content
- Provides `safe_to_continue?()` method for trap detection

#### `PaginatedArchiveScraper` (`app/services/paginated_archive_scraper.rb`)
- Iterates through paginated archive pages
- Finds next page links using multiple strategies
- Only follows same-origin links (safety feature)
- Extracts articles from each page

#### `WebFetcher::Live` (`app/services/web_fetcher/live.rb`)
- Makes HTTP requests
- Enforces robots.txt rules before each request
- Enforces crawl-delay with jitter
- Raises errors for disallowed paths

#### `PaginateArchiveJob` (`app/jobs/paginate_archive_job.rb`)
- Orchestrates pagination process
- Enforces hard limits (pages, posts, duration)
- Uses PaginationGuard for trap detection
- Handles errors and records halt reasons

### Same-Origin Safety

The `PaginatedArchiveScraper` only follows links from the same origin:

```ruby
def resolve_url(href)
  uri = URI.parse(href)
  if uri.absolute?
    # Only accept URLs from the same origin
    return nil unless href.start_with?(@origin)
    href
  else
    "#{@origin}#{href.start_with?('/') ? '' : '/'}#{href}"
  end
end
```

This prevents:
- Off-site navigation that could lead to infinite external links
- Cross-site attacks or traps
- Unintended scraping of other domains

### Queue Configuration

Pagination jobs run in the `archive_paginator` queue with very low concurrency:

```yaml
# config/queue.yml
- queues: [archive_paginator]
  threads: 1
  processes: 1
```

This ensures:
- Only one pagination job runs at a time per process
- Crawl-delays are properly respected
- Server load is minimized

---

## Summary

Retrofeed's scraping system implements comprehensive safety measures:

1. ✅ **Robots.txt compliance** - Respects site owners' crawling preferences
2. ✅ **Random delays with jitter** - Avoids predictable patterns and bot detection
3. ✅ **AI trap detection** - Detects circular URLs, page jumps, duplicate content, empty pages, duplicate posts
4. ✅ **Hard limits** - Prevents runaway jobs (500 pages, 10,000 posts, 30 minutes max)
5. ✅ **Same-origin safety** - Only follows links from the same domain
6. ✅ **Low concurrency** - Single-threaded pagination to respect rate limits

All safety measures are documented in code comments and enforced automatically. The system is designed to be respectful, safe, and resistant to traps while still being effective at discovering and scraping content.
