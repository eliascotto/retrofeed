# Crawling and Extraction System

This document is the full reference for how Retrofeed turns a website URL into
readable articles. It covers the two extraction phases, every service and job
involved, the customization layers, the playground debugger, and the known
complexity that makes some sites hard to onboard.

The last two sections ("Simplification proposals" and "Playground debugging
improvements") are forward-looking. Everything before them describes the system
**as it exists today**.

---

## 1. The two phases

Extraction is deliberately split into two independent phases. Each phase reads a
different kind of page and writes a different part of the `Article` record.

| Phase | Input | Output | Status today |
|---|---|---|---|
| **1. Archive extraction** | A website / archive URL (e.g. `/blog`) | `Article` records with `url`, `title`, `publication_date` (no body) | Live (automatic) |
| **2. Article extraction** | A single article URL | The same `Article` filled with `content_html`, `content_md`, `word_count`, `author`, refined `title`/`date` | On demand only, one article at a time (`FetchArticleContentJob`) |

Phase 1 answers "what articles exist on this blog?". Phase 2 answers "what does
each article say?". Crawling a site only runs phase 1, so in production a fresh
website ends up with a list of titled, dated, but bodyless articles. Phase 2
never runs automatically for a whole site: an article's body is fetched only when
a user asks for it (the "Download" button, or the API refresh endpoint), each of
which enqueues a single `FetchArticleContentJob`. The playground can also exercise
phase 2 on demand (see section 8).

---

## 2. Glossary

| Term | Meaning |
|---|---|
| **Archive page** | The page that lists a blog's posts (`/blog`, `/archive`, `/posts`, or a homepage that happens to list posts). |
| **Detection** | Figuring out *which URL* is the archive page for a domain. Done by `ArchivePageDetector`. |
| **Archive extraction** | Turning archive HTML into a list of `{url, title, date, tags}`. Done by `WebProcessor.extract_articles_from_archive`. |
| **Article extraction** | Turning a single article's HTML into clean content. Done by `WebProcessor.extract_article_content` -> `ExtractorClient` (defuddle). |
| **Custom detector** | A per-domain class that overrides detection *and* extraction wholesale (e.g. `SimonWillisonDetector`). |
| **Custom rule** | A per-domain declarative config that overrides individual fields (date/author/title/container/allowed external links). |
| **Defuddle** | The external Node.js extractor server (`ExtractorClient`) that produces clean article content. |
| **Fixture** | A cached copy of a fetched page used by the playground for offline, repeatable runs. |

---

## 3. End-to-end pipeline

```
ProcessWebsiteJob                         (entry point / orchestrator)
  |
  |-- WebProcessor.should_crawl_archive?  (new or stale site?)
  |       new site -> ArchivePageDetector.detect(url)   ===== DETECTION =====
  |                       returns Result(url, method, confidence, pagination)
  v
CrawlArchiveJob (Stage 1)                 ===== PHASE 1: ARCHIVE EXTRACTION =====
  |  fetch archive HTML
  |  WebProcessor.contains_valid_archive?            (validation gate)
  |  WebProcessor.extract_website_title / favicon
  |  WebProcessor.extract_articles_from_archive      (the extraction engine)
  |       -> [{url, title, date, tags}, ...]
  |  create Article records (TitleCleaner.clean_archive_title)
  |
  |-- if pagination eligible -> PaginateArchiveJob (Stage 1b)
  |                                 PaginatedArchiveScraper + PaginationGuard
  |                                 (repeats extract_articles_from_archive per page)
  |
  |-- status -> "completed" (no automatic content fetching)


User clicks "Download" on one article         ===== PHASE 2: ARTICLE EXTRACTION =====
  -> FetchArticleContentJob (single article, on demand)
        fetch article HTML
        WebProcessor.extract_article_content (ExtractorClient / defuddle)
        fill content_html/content_md/word_count, refine title/date
```

### Who triggers what

| Trigger | Path |
|---|---|
| User subscribes to a new site | `ProcessWebsiteJob` -> detection -> `CrawlArchiveJob` |
| User subscribes to an already-known domain | `ProcessWebsiteJob` does nothing (the site already has an `archive_url`) |
| Manual refresh (`Website#refresh_later`) | `CrawlArchiveJob.perform_later(archive_url, force: true)` directly (skips detection) |
| Scheduled refresh (`RefreshWebsitesJob`, stale sites) | `ProcessWebsiteJob.perform_later(website.archive_url)` |

Note the asymmetry: `ProcessWebsiteJob` only enqueues `CrawlArchiveJob` for
**new** domains. For existing domains it is essentially a no-op, because
detection has already happened once and the `archive_url` is stored. Re-crawls go
through `RefreshWebsitesJob` (which re-runs `ProcessWebsiteJob` with the stored
archive URL) or through `refresh_later` (which calls `CrawlArchiveJob` directly).

---

## 4. Detection: finding the archive URL

`ArchivePageDetector#detect` (`app/services/archive_page_detector.rb`) takes a
user URL and returns a `Result(url, method, confidence_score,
pagination_detected, notes)`. It tries strategies in order and returns the first
that succeeds; it raises `DetectionError` if all fail.

| # | Strategy | Method name | Confidence | What it does |
|---|---|---|---|---|
| 0 | Registry: known archive URL | `known_archive` | 1.0 | Hardcoded domain -> URL map (`Registry::KNOWN_ARCHIVES`). Verifies the URL is reachable. |
| 0 | Registry: custom detector class | (detector-defined) | (detector-defined) | A per-domain class (`Registry::DETECTORS`) takes over detection. |
| A | User URL is already an archive | `user_provided` | 1.0 | Validates the user URL with `contains_valid_archive?`. **Skipped if the user gave the homepage**, so dedicated archive paths get preferred. |
| B | Probe known paths | `known_path` | 0.9 | HEAD-then-GET each of `KNOWN_ARCHIVE_PATHS` (`/blog`, `/archive`, `/posts`, ...) and `.html` variants; validate each. |
| C | Link analysis on homepage | `link_analysis` | 0.5-0.85 (or 0.7 fallback) | Score candidate nav links by keywords, article-like DOM, dates, pagination. Prefer a dedicated archive page; fall back to the homepage if it is itself a valid archive. |
| D | Feed-assisted discovery | (varies) | (varies) | Last resort: parse RSS/Atom feeds to find post URLs. |

Key shared helpers:

- `contains_valid_archive?` (in `WebProcessor`) is the **validation gate** used by
  almost every strategy. See section 6.
- `detect_pagination` scans for `rel=next/prev`, pagination containers, page-number
  URL patterns, and "next/older" link text.
- `calculate_candidate_score` scores a candidate page using
  `ArchiveContainerExtractor` to focus on the main content area.

The detector fetches multiple pages per run (origin + each probe + each
candidate). In the playground these fetches are logged (section 8).

---

## 5. Stage 1 job: `CrawlArchiveJob`

`app/jobs/crawl_archive_job.rb` is the phase-1 orchestrator. Given an archive URL
it:

1. Sets `Website#processing_status = "crawling"`.
2. Fetches the archive HTML (`WebFetcher`).
3. **Validates** with `WebProcessor.contains_valid_archive?` (raises
   `InvalidArchiveError` on failure).
4. Fetches the homepage to extract the site title (`extract_website_title`) and
   favicon.
5. Persists the `Website` (name, `archive_url`, `last_crawled_at`, detection
   metadata) and moves status to `"extracting"`.
6. Enqueues `PaginateArchiveJob` if `Website#should_paginate?`.
7. Extracts articles (`WebProcessor.extract_articles_from_archive`).
8. Creates/updates `Article` records, cleaning titles with
   `TitleCleaner.clean_archive_title`.
9. Marks the site `"completed"` (unless pagination is still running, in which
   case `PaginateArchiveJob` finalizes it). Article bodies are never fetched
   automatically; that happens on demand per article (see section 8).

Errors are funneled through `ErrorReporter` and mark the `Website` as failed.

---

## 6. The validation gate: `contains_valid_archive?`

`WebProcessor.contains_valid_archive?(html, base_url, min_links: 5)` decides
whether a page is "an archive". It collects local links, drops the current page
and the bare root, and keeps only **article-like** paths using the same predicate
extraction uses (`ArticleExtractor.article_like_path?`, backed by
`ARTICLE_EXCLUDED_PATH_PATTERNS`). It then accepts the page if **any** of these
hold over that article-like set:

1. There are >= `min_links` article-like paths.
2. There are >= `min_links` date-based URLs (via
   `DateExtractor.extract_date_from_path`).
3. Some directory pattern (path minus last segment) has >= `min_links` links.

Because every check now operates on the article-like set, "is this a valid
archive?" and "is this link an article?" are decided by one predicate -- a page
can no longer validate on links that extraction would reject (the old "valid
archive, zero articles" case). Check 1 (the count) is the primary gate; the date
and directory counts mainly enrich the verdict (see below). This was proposal S3.

The boolean is a thin wrapper over
`WebProcessor.contains_valid_archive_with_reason?`, which returns an
`ArchiveVerdict` (`app/models/archive_verdict.rb`) carrying the link counts behind
the decision (`local_links_count`, `candidate_paths_count`, `article_like_count`,
`date_paths_count`, `top_pattern`/`top_pattern_count`, `passed_check`). The
playground uses it to explain a rejection (proposal P3).

---

## 7. The extraction engine: `extract_articles_from_archive`

`WebProcessor.extract_articles_from_archive(html, base_url)` is the heart of
phase 1. It returns an array of `{title, url, date, tags}`.

```
extract_articles_from_archive
  |
  |-- try_custom_extraction(html, base_url)        (custom detector override?)
  |       ArchivePageDetector::Registry.for_url -> detector.extract_articles
  |       returns immediately if a custom detector handles_extraction?
  |
  |-- else ArchiveExtractor.extract_articles(html, base_url)
```

`ArchiveExtractor` `include`s `WebProcessor::ArticleExtractor` and starts by
narrowing the search area with `ArchiveContainerExtractor.find_container`.

### 7.1 `ArchiveContainerExtractor` (scope narrowing)

`find_container(url, doc)` returns the element to search within:

1. A custom rule's `archive_container` config, if any.
2. Otherwise the first of `main, #content, #main, #main-content, .content,
   .main, .main-content, [role="main"]` that contains >= 2 links.
3. Otherwise `nil` (strategies fall back to the whole document).

This keeps nav/footer/sidebar links out of extraction.

### 7.2 `ArchiveExtractor` (the extraction engine)

`app/services/web_processor/archive_extractor.rb`. Three phases, each a
fallback for the previous:

| Phase | Approach | Accepted when |
|---|---|---|
| 1 | Try ~30 fast CSS selectors (`FAST_SELECTORS`: `article`, `ul.posts > li`, table rows, `[class*="post-item"]`, ...). | >= 3 containers with an article-like link. |
| 2 | Pattern discovery: sample the first 20 article-like links, infer the most common parent selector, then re-select all matches. | >= 3 matching containers. |
| 3 | Direct link extraction: just take every article-like link and derive a title/date from it. | Always (last resort). |

### 7.3 `ArticleExtractor` (shared predicates)

`app/services/web_processor/article_extractor.rb` provides the link-level rules
`ArchiveExtractor` relies on. The module is `extend self`, so its predicates are
callable both as instance methods (mixed into `ArchiveExtractor`) and at module
level (`ArticleExtractor.article_like_path?`) -- which is how the validation gate shares
the same "is this an article link?" predicate as extraction (proposal S3):

- `ARTICLE_EXCLUDED_PATH_PATTERNS` -- the canonical "not an article" prefix list
  (`/category`, `/tag`, `/page`, `/archives`, `/about`, `/contact`, `/author`,
  `/rss`, `/feed`, ...).
- `article_like_path?(path, base_path)` -- the predicate for "is this a real
  post link?".
- `find_article_links` / **`find_article_links_with_fate`** -- the latter returns
  a per-link `debug_entries` array recording why each link was kept or dropped
  (`rss_link`, `excluded_self`, `excluded_pattern:/tag`, `article_like`,
  `external`, ...). This is **the data the playground debug panel was designed to
  show, but nothing currently feeds it through** (see section 8 and proposal P1).
- `extract_article_data`, `extract_article_title`, `extract_tags`,
  `extract_table_row_data`, `sort_articles`.

---

## 8. Phase 2: article content extraction

Article bodies are fetched only on demand, one article at a time. There is no
automatic whole-site content fetching.

- `FetchArticleContentJob` fetches a single article's HTML and extracts its
  content. It is enqueued by `Articles::DownloadsController#create` (the
  "Download" button) and `Api::ArticlesController#refresh`, both of which gate on
  `WebProcessor.should_update_content?(article, force: true)` for rate limiting.
- `WebProcessor.extract_article_content(url, html:)` calls
  `ExtractorClient.extract` (the Node defuddle server, default `localhost:3880`,
  thread-local keep-alive connections). It then layers our own
  `DateExtractor` and `AuthorExtractor` on top of defuddle's output, because our
  date parsing is more reliable than defuddle's `published`.

---

## 9. Cross-cutting infrastructure

### 9.1 `WebFetcher` (four backends)

`app/services/web_fetcher.rb` chooses a backend by priority **Mock > Browser >
Live**:

| Backend | When | Notes |
|---|---|---|
| `Mock` | `MOCK_WEB_DATA=true` (dev) or `E2E_MOCK_DATA=true` (test) | Serves `test/fixtures/` HTML by domain mapping. |
| `Browser` | `USE_BROWSER_FETCHER=true` | Headless browser for JS-rendered pages; supports infinite scroll. |
| `Live` | default | Plain HTTP (HTTParty), follows redirects, returns `final_url`. |
| `Playground` | injected explicitly by the playground | Fixture-cache wrapper around Live/Browser; logs every fetch. |

`WebFetcher` also exposes `head` (used by detection probes) and exposes
`final_url` everywhere so callers can canonicalize after redirects.

### 9.2 Customization layers (three of them)

This is the part most likely to surprise a reader: there are **three separate
per-domain override mechanisms**, checked in different places.

| Layer | Class | Scope of override | Example sites |
|---|---|---|---|
| Known archive URL | `ArchivePageDetector::Registry::KNOWN_ARCHIVES` | Detection only (skip straight to a URL) | `shaggydev.com` |
| Custom detector | `ArchivePageDetector::Registry::DETECTORS` | Detection **and** extraction (whole class) | `simonwillison.net` |
| Custom rule | `WebProcessor::CustomRules::Registry` | Individual fields: date, author, title, archive container, allowed external links | `paulgraham.com`, `antirez.com` |

`CustomRules::Base` is a small declarative DSL (`host`, `date`, `author`,
`title`, `archive_container`, `allowed_external_domains`) where each field is a
config hash (`css`, `fallback_css`, `attr`, `regex`, `capture`, `transform`,
`static`). See proposal S2 about consolidating these.

### 9.3 Other services

| Service | Role |
|---|---|
| `DateExtractor` / `DateUtils` | Dates from JSON-LD, OpenGraph, `<time>`, CSS selectors, or URL path patterns. |
| `TitleCleaner` | Strips site-name suffixes; `detect_common_suffix` analyzes 60%+ of titles. |
| `AuthorExtractor` | Author from custom rule, meta tags, or defuddle output. |
| `FaviconExtractor` / `FaviconDownloader` | Find and attach the site favicon. |
| `UrlUtils` | URL normalization, domain/path extraction, local-link checks. |
| `RobotsTxt` | robots.txt parsing and crawl-delay enforcement (used by Live fetch). |
| `PaginationGuard` | Hard caps + trap detection for `PaginateArchiveJob`. |
| `ErrorReporter` | Structured error capture into error groups for observability. |

### 9.4 Website processing status

`Website#processing_status` moves through: `pending` -> `crawling` ->
`extracting` -> `completed` (or `failed`). `Website#processing?` is true for
`pending/crawling/extracting`. With content fetching disabled, sites reach
`completed` at the end of `CrawlArchiveJob` (or `PaginateArchiveJob`).

---

## 10. The playground (debug tool)

The playground (`/playground`, development/test only,
`app/controllers/playground_controller.rb`) is the primary tool for debugging why
a site does or does not extract correctly. It runs the **real** detection and
extraction code with `WebFetcher::Playground` injected, so all fetches are cached
as fixtures and repeatable offline.

### What it does

| Endpoint | Purpose |
|---|---|
| `GET /playground?website=URL` | Run detection + phase-1 extraction; render `results`. |
| `POST /playground` | Redirects to the GET form for shareable URLs. |
| `POST /playground/process_article` | Run phase-2 (`extract_article_content`) on a single URL; render `article_results`. |
| `GET/DELETE /playground/fixtures` | Manage the fixture cache. |

Options (query params): `max_pages`, `test_pagination`, `use_infinite_scroll`,
`max_scrolls`, `debug`, `skip_fixture`.

### What `results.html.erb` shows today

- **Archive Detection**: resolved URL, detector, method, strategy, confidence
  (with a post-extraction adjustment based on internal/external domain match),
  notes.
- **Article Domain Analysis** + **Confidence Score Breakdown**: how many
  extracted articles are internal vs external, and how that adjusted the score.
- **Pages Fetched**: every fetch during detection, tagged `probe` / `archive` /
  `pagination`, with source (`Cached`/`Live`) and size. This is fed by
  `Thread.current[:playground_fetch_log]`.
- **Articles Found**: the extracted list, internal links highlighted vs external.
- **Extraction Debug** (collapsible): a panel built to show `phase`,
  `phase_detail`, `containers_count`, `dropped_urls`, and a per-link
  `article_like_links` fate table.

### The gap: the debug panel is mostly empty

The view is fully built, but **the data is never produced**:

- The controller sets `extraction_debug = {}` and only ever adds `final_url` to
  it. It then calls the normal `WebProcessor.extract_articles_from_archive`,
  which has **no debug parameter and emits no trace**.
- `ArchiveExtractor` calls `find_article_links` (the
  non-fate variant) and never records which phase matched, which selector won,
  which containers were found, or which article-like links were dropped.
- `find_article_links_with_fate` exists and produces exactly the per-link
  `debug_entries` the view's `article_like_links` table expects -- but no caller
  uses it.

So in practice the playground can tell you **which archive URL was chosen** and
**whether the resulting links are on-domain**, but it cannot tell you **why a
specific post was missed** or **which phase/selector produced the result** --
which is exactly the information needed to debug a failing site. Closing this gap
is proposal P1.

---

## 11. Where it actually breaks (failure map)

A practical list of the failure modes this system hits, and where to look.

| Symptom | Likely cause | Where |
|---|---|---|
| "Could not detect an archive page" | All 5 detection strategies failed; homepage has < 5 article-like links and no known path. | `ArchivePageDetector#detect`, `contains_valid_archive?` |
| "The URL does not contain a valid archive" | Validation gate rejected the page even though it looks like an archive. Open the playground's "Archive Validation" verdict to see which check fell short. | `contains_valid_archive?` / `contains_valid_archive_with_reason?` (section 6). |
| Validates but few/no articles extracted | Extraction selectors did not match the site's markup; or `ArchiveContainerExtractor` narrowed to the wrong container; or links were dropped by `ARTICLE_EXCLUDED_PATH_PATTERNS`. | `ArchiveExtractor`, `ArchiveContainerExtractor`, `article_like_path?` |
| Many "External" articles | Archive links point off-domain (aggregators, link blogs) and aren't allow-listed. | `find_article_links`, custom rule `allowed_external_domains` |
| Wrong/empty dates | Site uses an unusual date format or location. | `DateExtractor`, custom rule `date` |
| Titles include the site name | Suffix detection hasn't run (it depends on phase-2 content, which is disabled). | `TitleCleaner`, `detect_and_store_title_suffix` |
| JS-rendered archive returns nothing | Live fetch sees an empty shell; needs the browser fetcher. | `WebFetcher::Browser`, `use_infinite_scroll` |

The recurring theme: **the decision-making is spread across detection,
validation, container narrowing, and three strategy phases, each with its own
heuristics, and none of them emit a trace.** When a site fails you cannot see
*which* step made the wrong call.

---

## 12. Simplification proposals

These are proposals, not yet implemented. They target the specific complexity
called out above. They are ordered by value-to-effort.

### S1. Collapse to a single extraction strategy (done)

**Problem:** `HybridStrategy` and `PatternBasedStrategy` overlapped heavily
(`good_container?`, parent-pattern discovery, scoring, direct-link fallback), but
`PatternBasedStrategy` was never selected in production. Two code paths had to be
read and kept in sync for one behavior.

**Done:** `PatternBasedStrategy` and the `strategy:` parameter on
`extract_articles_from_archive` are gone. With only one extractor left, the
`WebProcessor::Strategies` namespace was dropped too: the engine now lives at
`app/services/web_processor/archive_extractor.rb` as
`WebProcessor::ArchiveExtractor`, alongside the other `web_processor/`
extractors. The three fallback phases are unchanged.

### S2. Unify the three per-domain override layers (done)

**Problem:** When a domain needs special handling, there are three unrelated
places it might live (the same three registries from section 9.2):

| If you need to... | You edit | Which is consulted in... |
|---|---|---|
| Skip detection and hardcode the archive URL | `Registry::KNOWN_ARCHIVES` | `ArchivePageDetector#detect` (strategy 0) |
| Replace detection *and* extraction with custom code | `Registry::DETECTORS` | `#detect` (strategy 0) **and** `extract_articles_from_archive` (`try_custom_extraction`) |
| Override one field (date, author, title, container, external links) | `WebProcessor::CustomRules::Registry` | `ArchiveContainerExtractor`, `DateExtractor`, `AuthorExtractor`, ... |

These are three different data structures, in three files, read at different
points in the pipeline, with no link between them. The cost shows up twice:

- **Onboarding a hard site:** you must already know which layer solves your
  problem. "The dates are wrong" -> custom rule; "the whole archive is
  JS-rendered nonsense" -> custom detector; "detection picks the wrong page" ->
  known archive URL. Pick the wrong layer and you write code that never runs.
- **Tracing a domain:** to answer "what is special about `simonwillison.net`?"
  you have to grep three registries, because any subset of them may have an
  entry, and nothing tells you which.

**Proposal:** Introduce one `SiteProfile` concept, keyed by domain, that can
optionally declare *any subset* of the three concerns:

```ruby
class SiteProfile::SimonWillison < SiteProfile
  host "simonwillison.net"

  # only the keys this site actually needs; everything else falls back
  # to the default detection + extraction pipeline
  detect           { |url| ... }   # custom-detector escape hatch
  extract_articles { |html, url| ... }
  date css: "time.dt-published", attr: "datetime"
end
```

Lookup collapses to a single call -- `SiteProfile.for("simonwillison.net")` --
and each site is **one file** that lists everything special about it. The
existing mechanisms don't have to change underneath: `SiteProfile` can dispatch
to the current detectors/rules internally. What changes is that the three call
sites (`#detect`, `try_custom_extraction`, the field extractors) each ask the
one profile for the one thing they need, instead of consulting their own
registry.

**Risk:** Medium (touches two registries and their call sites). Can be done
incrementally: introduce `SiteProfile` as a thin facade over the existing three
registries first (no behavior change), then migrate sites one at a time, then
delete the old registries once they're empty.

### S3. Single source of truth for "is this an article link?" (done)

**Problem:** `contains_valid_archive?` had its own inline exclusion list that
diverged from `ARTICLE_EXCLUDED_PATH_PATTERNS`. Validation and extraction could
therefore disagree, producing the confusing "valid archive, zero articles" (and
the reverse) cases.

**Done:** `ArticleExtractor` is now `extend self`, and `contains_valid_archive?`
filters candidate links through `ArticleExtractor.article_like_path?` before
running all three checks, so the same predicate decides both "is this a valid
archive?" and "is this link an article?". One list, one behavior. Coverage in
`test/services/web_processor/contains_valid_archive_test.rb` (groups C2, F, G pin
the new behavior near the threshold).

Note this also tightened two edge cases vs the old inline list: the predicate
matches whole path segments, so links that merely *start with* an excluded word
(`/aviation`, `/about-react`) are now correctly kept, while links under a truly
excluded prefix (`/category/...`, `/tag/...`) are rejected even when dated.

### S4. (done) Remove automatic content fetching

Automatic, whole-site content fetching (`BatchFetchArticleContentJob`,
`ArticleProcessingCompleteJob`, and the `content_fetching_enabled?` flag) has been
removed. Article bodies are now fetched only on demand, one article at a time, via
`FetchArticleContentJob`. This deleted a large dormant subsystem and made the
crawl lifecycle simply: crawl archive -> create article records -> mark the
website `"completed"`.

### S5. (Optional) flatten the job chain

The `ProcessWebsiteJob -> CrawlArchiveJob -> PaginateArchiveJob` chain threads
`processing_status` through several classes, and "who finalizes the status" is
conditional (Crawl vs Paginate). Consider documenting the status-ownership rules
explicitly, or moving finalization into a single
`Website#finalize_processing!` that each job calls, so the terminal transition
lives in one place.

---

## 13. Playground debugging improvements

These make the playground actually answer "where did it go wrong?". P1 is the
highest-value change in this whole document.

### P1. Wire up the extraction trace (the panel is already built)

**Problem:** The `Extraction Debug` panel renders `phase`, `phase_detail`,
`containers_count`, `dropped_urls`, and the per-link `article_like_links` fate
table -- but nothing populates them. The data already exists
(`find_article_links_with_fate`).

**Proposal:** Give the extraction engine an optional debug sink and thread it to
the playground:

1. Add an optional `debug:` hash (or a small `ExtractionTrace` object) to
   `extract_articles_from_archive` and to `ArchiveExtractor#extract_articles`.
2. Have the strategy record, as it runs: the chosen path (custom detector vs
   hybrid), the **winning phase** and **matched selector** (`phase`,
   `phase_detail`), `containers_count`, and the result of
   `find_article_links_with_fate` as `article_like_links`.
3. Compute `dropped_urls` = article-like links that were found but did not make
   the final list (different container group / filtered out).
4. In `PlaygroundController`, pass the debug hash in and stop discarding it.

This turns the panel from empty boilerplate into a per-link explanation of every
inclusion/exclusion decision, with zero new UI work.

**Risk:** Low. The debug sink is opt-in, so production callers pass `nil` and pay nothing.

### P2. A detection decision log

**Problem:** "Pages Fetched" shows *what* was fetched but not *why* each strategy
accepted or rejected a page. When detection picks the wrong URL you can't see the
reasoning.

**Proposal:** Have `ArchivePageDetector` append structured decision entries
(`strategy`, `candidate_url`, `accepted?`, `reason`, `score`) to a thread-local
log when running under the playground fetcher, mirroring the existing
`playground_fetch_log`. Render them as a "Detection Trace" table next to "Pages
Fetched".

**Risk:** Low. Additive and playground-gated.

### P3. Surface the validation verdict (done)

**Problem:** `contains_valid_archive?` returned a bare boolean; when it rejected a
page the playground only showed the generic error.

**Done:** `contains_valid_archive_with_reason?` returns an `ArchiveVerdict` that
reports the passing check and the link counts involved (`local_links_count`,
`candidate_paths_count`, `article_like_count`, `date_paths_count`, `top_pattern`/
`top_pattern_count`). When detection rejects the user's URL the playground
computes the verdict for that URL and renders it as an "Archive Validation" table
(and, in `debug` mode, for the chosen archive page too). Pairs with S3: the shared
predicate means the same numbers explain both validation and extraction.

### P4. Strategy / container "what-if" view

**Problem:** When extraction picks the wrong container or phase, there's no way to
see the alternatives.

**Proposal (stretch):** In debug mode, run all Hybrid phases (and report each
phase's would-be result count) and list the candidate containers
`ArchiveContainerExtractor` considered with their link counts, so you can see
*why* a particular container/phase won. Builds directly on P1's trace object.

**Risk:** Medium (more work in the strategy), but entirely opt-in.

---

## 14. Suggested order of work

1. ~~**P1** (wire the extraction trace)~~ -- done.
2. ~~**S3** (shared article-link predicate) + **P3** (validation verdict)~~ -- done;
   fixes the most confusing class of failure and makes the playground explain it.
3. ~~**S1** (delete the dead strategy)~~ -- done; removed a whole branch from the model.
4. **P2** (detection trace) -- done; completes the "see every decision" story.
5. **S2** (unify override layers) -- done; the biggest structural simplification; do it
   once the traces make per-site behavior easy to verify.
6. ~~**S4** (remove automatic content fetching)~~ -- done; phase 2 is on demand only.
7. **S5 / P4** -- cleanup and stretch goals.
