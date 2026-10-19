**Project Specification — retrofeed**
**Stack:** Rails 8 + Hotwire + SQLite
**Scope:** Minimal, polished toy project intended for public use

---

## 1. Concept

**retrofeed** is a minimal, literary-retro RSS alternative designed to help readers explore the *entire* archive of a blog—not just its latest posts.

Users submit the archive URL of a blog (e.g. `/archive`, `/posts`, `/blog/yyyy/`), and retrofeed scrapes:

* the list of posts (titles + links),
* publication dates (when available),
* tags/categories,
* the full content of each article.

retrofeed stores all articles in a local database and presents them in a clean, chronological interface. Unlike traditional RSS—which only surfaces new or recent content—retrofeed encourages slow, intentional discovery of older writing.

The goal is to offer a small, timeless reading tool: no algorithm, no feeds driven by novelty, no infinite distraction—just a personal library of blogs, from oldest to newest or vice-versa.

---

## 2. Core Features

### 2.1 Blog ingestion

Given a blog archive URL, the system should:

* Fetch the archive page (HTML).
* Extract all article links.
* For each link:

  * Fetch and parse the article page.
  * Extract:

    * title
    * publication date (if available)
    * tags/categories (if present)
    * main content (clean HTML, Instapaper-style)
  * Store article content locally if not already saved.

### 2.2 Articles database (SQLite)

* Blog

  * name (optional)
  * base URL
  * archive URL
* Article

  * blog_id
  * title
  * url
  * content_html
  * publication_date (nullable)
  * tags (string, JSON text, or separate table)
  * read_at (nullable)
  * created_at / updated_at

SQLite is sufficient for the toy release; can migrate to Postgres later if needed.

### 2.3 Reading interface

* List of blogs.
* For each blog:

  * List of articles (oldest → newest or newest → oldest).
  * Filters: unread only, by tag, by year.
* Article view:

  * clean typography
  * adjustable font size
  * dark/light toggle
  * “Mark as read” button.

### 2.4 Read-state tracking

Users should be able to:

* mark an article as read/unread
* view progress within each blog
* quickly continue where they left off

### 2.5 Hotwire integration

Use Turbo for:

* marking read/unread without page reload
* inline updating of article lists
* background ingestion progress updates (optional)

Stimulus for:

* small UI interactions (font size, dark mode).

---

## 3. Minimal UX Flow

### Add blog

1. User inputs blog archive URL
2. Click “Add”
3. retrofeed creates a new Blog entry
4. retrofeed begins scraping
5. Articles appear gradually as they’re parsed (Turbo streams optional)

### Read blog

1. Select blog
2. Browse article list
3. Open any article
4. Mark read/unread
5. Continue to next/previous with keyboard shortcuts (optional)

---

## 4. Scraping Strategy

### Phase 1 — Basic extraction

* Fetch archive page
* Extract article URLs

### Phase 2 — Article extraction

* Fetch each article
* Run HTML through:

  * a readability gem (e.g., `readability-rails` or custom service using Nokogiri)
* Extract metadata:

  * title: `<title>` or `<h1>`
  * date: parse common patterns
  * tags: parse `<a>` in category/tag lists
* Store content locally

### Phase 3 — Scheduling (minimal)

* Manually retrigger scraping to fetch new posts
* (Optional) daily background job to update blogs

### Phase 4 — Error handling

* Store failed URLs
* Allow manual retry

---

## 5. Non-goals (for clarity)

retrofeed intentionally does **not** aim to:

* be a general web crawler
* support complex feed formats (Atom, custom APIs)
* sync across devices
* have multi-user accounts or auth
* expose a public API
* implement annotations or highlights (maybe later)

Focus remains on a *personal* literary reading tool.

---

## 6. Technical Overview

### Backend

* Rails 8
* Postgres
* ActiveJob (inline adapter or GoodJob later)
* HTTP client (e.g. `http`, `faraday`, or `net/http`)
* HTML parsing with Nokogiri
* Readability extraction gem or custom cleaner

### Frontend

* Hotwire (Turbo + Stimulus)
* Simple Tailwind setup for typography (optional but useful)
* DaisyUI

### Structure

* `User` model
* `Blog` model
* `Article` model
* `BlogScraper` service
* `ArticleScraper` service
* Async job: `BlogIngestJob` (optional for now)

---

## 7. Minimum Publishable Version (MPV)

To release a usable minimal version:

1. Add a blog via URL
2. Scrape archive → scrape all articles
3. Show blog list
4. Show article list with read/unread
5. Simple article reader page
6. Mark as read/unread (Turbo Stream)
7. Nice typography
8. Handle basic errors
9. Simple empty state pages

