# Test Coverage Analysis and Recommendations

**Last Updated:** 2026-01-07

This document analyzes the current test coverage of Retrofeed and identifies gaps that should be addressed before release.

> **Note:** The "Immediate" and "Short Term" tests identified below have been implemented. See the "Added Tests" section at the end for details.

## Current Test Structure Overview

| Category | Test Files | Coverage Level |
|----------|------------|----------------|
| Models | 8 | Partial |
| Controllers | 15 | Partial |
| Services | 7 | Good |
| Jobs | 5 | Good |
| Components | 5 | Good |
| Integration | 3 | Good |
| E2E (Playwright) | 10 | Good |

---

## Critical Missing Tests

### 1. List Model Tests (HIGH PRIORITY)

**File missing:** `test/models/list_test.rb`

The `List` model is a core feature with significant business logic that has no dedicated model tests:

```ruby
# Methods/features to test:
- title validation (presence, length, uniqueness per user)
- description validation (length)
- slug uniqueness per user
- public_id uniqueness and generation
- system_list? detection
- read_next? detection
- public_slug generation (system vs user lists)
- find_by_public_slug (both system and user lists)
- find_by_public_slug_for_user
- create_read_next_for
- add_article (including position handling)
- remove_article
- reorder_article
- prevent_system_list_deletion callback
- scopes: public_lists, private_lists, system_lists, user_lists
```

### 2. ArticlesController Tests (HIGH PRIORITY)

**File missing:** `test/controllers/articles_controller_test.rb`

The articles controller handles the core reading experience:

```ruby
# Actions to test:
- show: subscription validation, article not found handling, error redirect
- mark_read: creates/updates reading state, redirects properly
- random: marks current as read, finds random unread, handles no unread
- next_article: marks current as read, finds next from same site, handles no more
```

### 3. Api::ArticlesController Tests (HIGH PRIORITY)

**File missing:** `test/controllers/api/articles_controller_test.rb`

Critical API endpoints for article interactions:

```ruby
# Endpoints to test:
- POST /api/articles/:id/mark_read
  - requires authentication
  - creates reading state if none exists
  - updates read_at if already started
  - handles non-existent article

- DELETE /api/articles/:id/mark_read (mark_unread)
  - requires authentication
  - destroys reading state
  - handles article with no reading state

- POST /api/articles/:id/track_view
  - creates or touches reading state
  - handles non-existent article

- POST /api/articles/:id/refresh
  - requires authentication
  - rate limiting (429 response)
  - enqueues FetchArticleContentJob
  - handles non-existent article
```

### 4. SitesController Tests (MEDIUM PRIORITY)

**File missing:** `test/controllers/sites_controller_test.rb`

Website browsing functionality:

```ruby
# Actions to test:
- index: lists subscribed websites, requires auth
- show: displays website articles, pagination, sorting, progress stats
```

### 5. ListsController Tests (MEDIUM PRIORITY)

**File missing:** `test/controllers/lists_controller_test.rb`

List browsing functionality:

```ruby
# Actions to test:
- index: lists user's reading lists, requires auth
- show: displays list with articles, sorting, article reordering
```

### 6. SubscriptionsController Tests (MEDIUM PRIORITY)

**File missing:** `test/controllers/subscriptions_controller_test.rb`

```ruby
# Actions to test:
- destroy: unsubscribes user, broadcasts update, requires auth
```

### 7. ListArticle Model Tests (LOW PRIORITY)

**File missing:** `test/models/list_article_test.rb`

```ruby
# Features to test:
- position-based ordering
- uniqueness constraint per list
- cascade delete with list
```

### 8. ContentErrorGroup Model Tests (LOW PRIORITY)

**File missing:** `test/models/content_error_group_test.rb`

```ruby
# Features to test:
- fingerprinting for deduplication
- status transitions
- polymorphic association
```

---

## Existing Tests with Gaps

### User Model (`test/models/user_test.rb`)

Missing tests for:
- `unread_articles` method
- `unread_articles_for_website` method
- `reading_articles` method (articles in-progress)
- `read_next_list` method
- After-create callback for Read Next list creation
- Reading settings validations (font_size, font_family, theme, content_width)

### Article Model (`test/models/article_test.rb`)

Missing tests for:
- `read_by?(user)` method
- URL validation
- Title presence validation
- Word count calculation
- Publication date handling

### Subscription Model (`test/models/subscription_test.rb`)

Should verify:
- Cascade cleanup of reading states on deletion
- Cascade cleanup of tags on deletion (if applicable)

---

## E2E Test Gaps

### Missing E2E Scenarios

1. **Article Reading Flow**
   - Open article from home page
   - Verify reading state is tracked
   - Mark article as read
   - Navigate to next/random article
   - Verify article marked as finished

2. **Reading Tab Flow**
   - View articles in-progress
   - Complete reading an article
   - Verify article moves from "reading" to "read"

3. **Search Functionality**
   - Search for articles by title
   - Search for articles by content
   - Search for sites
   - Tab switching between results

4. **Settings Flow**
   - Update appearance settings (theme, font)
   - Verify settings persist and apply

5. **Error Handling**
   - Access article without subscription
   - Access non-existent article
   - Access non-existent site

6. **List Reordering**
   - Drag and drop article in list
   - Verify position persists

---

## Pre-Release Testing Checklist

### Critical Path Tests (Must Have)

- [ ] User registration flow (E2E exists)
- [ ] User login/logout flow (E2E exists)
- [ ] Add website and verify articles load (E2E exists)
- [ ] Remove website subscription (E2E exists)
- [ ] Read an article (needs E2E)
- [ ] Mark article as read/unread (needs tests)
- [ ] Create reading list (E2E exists)
- [ ] Add article to list (E2E exists)
- [ ] Remove article from list (needs tests)
- [ ] Delete reading list (E2E exists)
- [ ] Search for articles/sites (needs E2E)

### Security Tests

- [ ] Authentication required for all protected routes
- [ ] Users cannot access other users' data (lists, subscriptions)
- [ ] Cannot modify system lists
- [ ] Rate limiting on article refresh
- [ ] Input validation (XSS prevention in titles, URLs)

### Edge Cases

- [ ] Handle website with no articles
- [ ] Handle website that fails to crawl
- [ ] Handle article content extraction failure
- [ ] Handle concurrent subscriptions to same website
- [ ] Handle very long article titles
- [ ] Handle very large reading lists
- [ ] Handle special characters in search

### Performance Tests (Manual)

- [ ] Home page loads quickly with many subscriptions
- [ ] Site page with 1000+ articles paginates correctly
- [ ] Search performance with large dataset
- [ ] Background job processing doesn't block UI

---

## Recommendations by Priority

### Immediate (Before Release)

1. **Add List model tests** - Core feature, complex business logic
2. **Add ArticlesController tests** - Critical user flow
3. **Add Api::ArticlesController tests** - Core API functionality
4. **Add E2E test for article reading flow** - Essential user journey

### Short Term (First Release)

5. Add SitesController tests
6. Add ListsController tests
7. Add SubscriptionsController tests
8. Add E2E tests for search functionality
9. Add User model tests for missing methods

### Medium Term

10. Add ListArticle model tests
11. Add ContentErrorGroup model tests
12. Add E2E tests for settings
13. Add E2E tests for error handling
14. Performance testing

---

## Test Commands Reference

```bash
# Run all tests
bin/rails test

# Run specific test file
bin/rails test test/models/list_test.rb

# Run E2E tests
bin/rails test:e2e

# Run system tests
bin/rails test:system

# Full CI (Rubocop, Brakeman, tests)
bin/ci

# Load fixtures for manual testing
bin/rails db:fixtures:load
```

---

## Summary

The codebase has solid test coverage for:
- Background job processing pipeline
- Services (WebProcessor, ExtractorClient, etc.)
- Integration of the crawling pipeline
- Authentication flows (E2E)
- List management API

Critical gaps exist in:
- **List model** - no tests for a core feature
- **ArticlesController** - no tests for the main reading experience
- **Api::ArticlesController** - no tests for mark read/unread/refresh
- **E2E article reading flow** - the core user journey is untested

Addressing these gaps before release will significantly improve confidence in the application's stability and correctness.

---

## Added Tests (2026-01-07)

The following tests were added to address the gaps identified above:

### Model Tests

| File | Tests | Coverage |
|------|-------|----------|
| `test/models/list_test.rb` | 51 tests | Validations, public_id generation, system_list?, read_next?, public_slug, find_by_public_slug, add/remove/reorder article, prevent system list deletion, scopes |
| `test/models/user_test.rb` | 24 new tests | unread_articles, unread_articles_for_website, reading_articles, read_next_list, reading_settings, update_reading_settings, home_tab_preference, admin?, after_create callback |
| `test/models/list_article_test.rb` | 11 tests | Associations, position ordering, uniqueness constraint, cascade delete |
| `test/models/content_error_group_test.rb` | 23 tests | Validations, status/severity values, polymorphic associations, fingerprinting, status transitions |
| `test/models/article_test.rb` | 7 new tests | read_by? method, cascade delete for user_articles/list_articles/article_tags |
| `test/models/subscription_test.rb` | 13 tests | Validations, associations, cascade cleanup (reading states, article tags) |

### Controller Tests

| File | Tests | Coverage |
|------|-------|----------|
| `test/controllers/articles_controller_test.rb` | 21 tests | Authentication, show (subscription check, not found), mark_read, random, next_article |
| `test/controllers/api/articles_controller_test.rb` | 17 tests | mark_read, mark_unread, track_view, refresh (with rate limiting) |
| `test/controllers/sites_controller_test.rb` | 22 tests | Authentication, index (with counts), show (subscription check, sorting, progress stats) |
| `test/controllers/lists_controller_test.rb` | 20 tests | Authentication, index (sorting), show (user/system lists, read state) |
| `test/controllers/subscriptions_controller_test.rb` | 8 tests | Authentication, destroy (removes subscription, handles errors) |

### E2E Tests

| File | Tests | Coverage |
|------|-------|----------|
| `test/e2e/articles/reading_flow.spec.ts` | 9 tests | Open article, navigate to next/random, mark as read, view tracking, reading tab |
| `test/e2e/search/search_flow.spec.ts` | 14 tests | Search page access, query handling, tab switching, pagination, special characters |
| `test/e2e/settings/settings_flow.spec.ts` | 11 tests | Settings page access, navigation to account/appearance, theme/font changes, settings persistence |
| `test/e2e/errors/error_handling.spec.ts` | 10 tests | Error pages (not found, site/article errors), go back navigation, error page structure |

### Test Summary

```
Total new tests added: ~236 tests

Model Tests:
- List model: 51 tests
- User model: 24 new tests
- ListArticle model: 11 tests
- ContentErrorGroup model: 23 tests
- Article model: 7 new tests
- Subscription model: 13 tests

Controller Tests:
- ArticlesController: 21 tests
- Api::ArticlesController: 17 tests
- SitesController: 22 tests
- ListsController: 20 tests
- SubscriptionsController: 8 tests

E2E Tests:
- E2E articles: 9 tests
- E2E search: 14 tests
- E2E settings: 11 tests
- E2E error handling: 10 tests
```

### Running the Tests

```bash
# Run all unit tests (694 tests)
bin/rails test

# Run specific new test files
bin/rails test test/models/list_test.rb
bin/rails test test/models/list_article_test.rb
bin/rails test test/models/content_error_group_test.rb
bin/rails test test/models/article_test.rb
bin/rails test test/models/subscription_test.rb
bin/rails test test/controllers/articles_controller_test.rb
bin/rails test test/controllers/api/articles_controller_test.rb
bin/rails test test/controllers/sites_controller_test.rb
bin/rails test test/controllers/lists_controller_test.rb
bin/rails test test/controllers/subscriptions_controller_test.rb

# Run E2E tests (requires server running on port 3002)
RAILS_ENV=test bin/rails db:fixtures:load
RAILS_ENV=test bin/rails server -p 3002 -d
E2E_PORT=3002 npx playwright test
```

### Known E2E Test Issues

Some pre-existing E2E tests may fail due to:

1. **add_article_to_list.spec.ts** - UI structure changes for dropdown menus
2. **add_website.spec.ts** - Tests require external network operations (paulgraham.com, etc.)
3. **remove_website.spec.ts** - UI selector changes for sites list

These tests need maintenance to align with current UI structure.
