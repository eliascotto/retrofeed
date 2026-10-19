# Retrofeed E2E Test Plan (Playwright)

This document outlines the E2E test cases for the MVP, prioritized by importance and designed to avoid flaky tests.

## Test Strategy

### Avoiding Flakiness
- **Use fixtures** for data setup (preloaded articles, websites, users)
- **Simulate job states** via fixtures rather than waiting for real async jobs
- **Test UI feedback** for async operations (progress bars, status messages) without waiting for completion
- **Deterministic data** - all test data comes from fixtures with known values

### Test User
- Email: `admin@retrofeed.com`
- Password: `password123`
- URL: `http://retrofeed.localhost:3000`

New users can be created during setup for testing purposes.

---

## Priority 1: Authentication (Critical Path)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 1.1 | Login with valid credentials | Visit /login, enter valid email/password, submit | Redirects to home, shows user content |
| 1.2 | Login with invalid email | Visit /login, enter non-existent email, submit | Shows error "Invalid email or password" |
| 1.3 | Login with wrong password | Visit /login, enter valid email + wrong password | Shows error "Invalid email or password" |
| 1.4 | Logout | Click logout link/button | Redirects to login, session cleared |
| 1.5 | Unauthenticated access to protected page | Visit /sites without login | Redirects to /login |
| 1.6 | Signup step 1 - valid data | Visit /signup, enter email/password | Proceeds to handle selection |
| 1.7 | Signup step 1 - invalid email | Visit /signup, enter invalid email format | Shows validation error |
| 1.8 | Signup step 1 - short password | Visit /signup, enter password < 8 chars | Shows validation error |
| 1.9 | Signup step 2 - valid handle | Complete step 1, enter valid handle | Account created, redirects to home |
| 1.10 | Signup step 2 - invalid handle | Complete step 1, enter handle with spaces/special chars | Shows validation error |
| 1.11 | Signup step 2 - duplicate handle | Complete step 1, enter existing handle | Shows "already taken" error |

---

## Priority 2: Website Management (Fundamental Action)

### Adding Websites - Happy Path

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 2.1 | Add website - valid URL | Open add site dialog, enter valid blog URL, submit | Shows "Processing..." state, job initiated |
| 2.2 | Add website - URL normalization | Enter URL without https://, submit | URL normalized, processing starts |
| 2.3 | Add website - already subscribed | Enter URL of already subscribed site | Shows appropriate message (already added) |

### Adding Websites - Error Cases

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 2.4 | Add website - empty URL | Submit with empty URL field | Validation error "URL required" |
| 2.5 | Add website - invalid URL format | Enter "not-a-url", submit | Validation error "Invalid URL" |
| 2.6 | Add website - unreachable domain | Enter URL with non-existent domain | Error "Could not reach website" |
| 2.7 | Add website - non-blog site | Enter URL of site without articles (e.g., google.com) | Error "No articles found" or similar |
| 2.8 | Add website - URL returns 404 | Enter URL that returns 404 | Error handling shown |
| 2.9 | Add website - URL returns 500 | Enter URL of broken server | Error handling shown |

### Processing Progress (Using Fixtures)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 2.10 | Show processing progress - 0% | Load fixture: website with 100 articles, 0 with content | Progress bar shows 0%, "Processing..." |
| 2.11 | Show processing progress - 50% | Load fixture: website with 100 articles, 50 with content | Progress bar shows 50% |
| 2.12 | Show processing progress - 100% | Load fixture: website with 100 articles, all with content | Progress complete, articles accessible |
| 2.13 | Processing indicator on sites list | Visit /sites with mixed-progress websites | Each site shows correct progress indicator |
| 2.14 | Processing indicator on site detail | Visit /sites/:id for processing website | Shows progress bar with article count |

### Removing Websites

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 2.15 | Unsubscribe from website | Visit /sites/:id, click unsubscribe, confirm | Removed from sites list, articles gone from feed |
| 2.16 | Unsubscribe clears reading states | Unsubscribe from site with read articles | Reading states for that site removed |
| 2.17 | Cancel unsubscribe | Click unsubscribe, cancel confirmation | Site remains subscribed |

### Refresh Actions

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 2.18 | Refresh website archive | Click refresh on site detail | New job started, UI shows refreshing state |
| 2.19 | Refresh single article | Click refresh on article with failed content | Article content re-fetched |

---

## Priority 3: Article Reading (Core Feature)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 3.1 | View article from home feed | Click article title in feed | Article page loads with full content |
| 3.2 | Article view tracks reading | Open article page | ReadingState created (via Stimulus) |
| 3.3 | Mark article as read | Open article, click "Mark as Read" | Article marked, visual confirmation |
| 3.4 | Mark article as unread | From read article, click "Mark as Unread" | Article returns to unread state |
| 3.5 | Navigate to next article | Click "Next" on article page | Loads next unread from same site |
| 3.6 | Next article - no more unread | Click "Next" when no more unread from site | Appropriate message or disabled button |
| 3.7 | Navigate to random article | Click "Random" on article page | Loads random unread article |
| 3.8 | Random article - all read | Click "Random" when all articles read | Appropriate message |
| 3.9 | Article content rendering | Open article with HTML content | Content renders correctly (no raw HTML) |
| 3.10 | Article metadata display | Open article | Shows title, site name, word count, date |

---

## Priority 4: Home Feed & Navigation

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 4.1 | Home shows unread articles | Visit home page | Displays unread articles from subscribed sites |
| 4.2 | Home - Recent tab | Click "Recent" tab | Shows articles sorted by publication date |
| 4.3 | Home - Reading tab | Click "Reading" tab | Shows in-progress articles (opened but not finished) |
| 4.4 | Home - empty state | User with no subscriptions | Shows empty state with CTA to add sites |
| 4.5 | Sites index page | Visit /sites | Lists all subscribed sites with unread counts |
| 4.6 | Site detail page | Visit /sites/:id | Shows site info and article list |
| 4.7 | Site detail - filter by read | Toggle read/unread filter | List updates to show only matching articles |
| 4.8 | Site detail - sort options | Change sort order | Articles reorder correctly |

---

## Priority 5: Search

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 5.1 | Search articles by title | Enter title keyword in search | Shows matching articles |
| 5.2 | Search articles by content | Enter content keyword in search | Shows articles containing keyword |
| 5.3 | Search websites by name | Enter site name in search | Shows matching websites |
| 5.4 | Search - no results | Enter gibberish query | Shows "No results found" message |
| 5.5 | Search - empty query | Submit empty search | Handles gracefully (redirect or message) |
| 5.6 | Search respects subscriptions | Search for article from unsubscribed site | Article not shown in results |
| 5.7 | Search pagination | Search with many results | Pagination works correctly |

---

## Priority 6: Lists (Read Next)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 6.1 | Add article to Read Next | Click "Save to Read Next" on article | Article added, confirmation shown |
| 6.2 | Add article already in list | Try to add duplicate | Appropriate handling (no duplicate or message) |
| 6.3 | View Read Next list | Navigate to Read Next list | Shows saved articles in order |
| 6.4 | Remove article from Read Next | Click remove on list item | Article removed from list |
| 6.5 | Read Next persists | Add article, logout, login | Article still in list |

---

## Priority 7: Settings & Appearance

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 7.1 | Change theme to dark | Go to settings, select dark theme | UI switches to dark mode |
| 7.2 | Change theme to light | Go to settings, select light theme | UI switches to light mode |
| 7.3 | Theme persists | Change theme, refresh page | Theme remains |
| 7.4 | Change font size | Adjust font size setting | Article text size changes |
| 7.5 | Change font family | Select different font family | Article font changes |
| 7.6 | Change content width | Adjust content width setting | Article container width changes |
| 7.7 | Settings navigation | Click through all settings sections | All pages load correctly |

---

## Fixture Requirements

To support these tests, the following fixtures are needed:

### Users
- `admin` - Main test user with subscriptions
- `new_user` - Fresh user with no subscriptions (for empty states)
- `user_for_signup` - Reserved email for signup tests

### Websites
- `blog_complete` - Website with 100% processed articles
- `blog_processing_50` - Website with 50% processed articles (50/100)
- `blog_processing_0` - Website with 0% processed articles (0/100)
- `blog_empty` - Website with no articles found
- `blog_unsubscribed` - Website user is not subscribed to

### Articles
- Multiple articles per website (at least 10 for pagination tests)
- Mix of read/unread states
- Mix of with/without content (for progress testing)
- Articles with various publication dates (for sorting tests)

### Lists
- `read_next` - System list with some articles
- `custom_list` - User-created list for testing

### Reading States
- Mix of read and in-progress states for home feed tab testing

---

## Implementation Notes

### Test Organization
```
test/e2e/
  authentication/
    login.spec.ts
    logout.spec.ts
    signup.spec.ts
  websites/
    add_website.spec.ts
    remove_website.spec.ts
    processing_progress.spec.ts
  articles/
    reading.spec.ts
    navigation.spec.ts
  home/
    feed.spec.ts
    tabs.spec.ts
  search/
    search.spec.ts
  lists/
    read_next.spec.ts
  settings/
    appearance.spec.ts
```

### Before Each Test
1. Reset database to known state (load fixtures)
2. Clear browser state (cookies, local storage)

### Handling Async Operations
- For website addition: Test the UI feedback (loading state, error messages) not job completion
- For progress: Use fixtures with pre-set progress states
- Use `waitFor` for UI state changes, not arbitrary timeouts

### Selectors Strategy
- Prefer `data-testid` attributes for stability
- Use semantic selectors (role, label) where appropriate
- Avoid brittle CSS class selectors

---

## Test Count Summary

| Priority | Category | Test Count |
|----------|----------|------------|
| 1 | Authentication | 11 |
| 2 | Website Management | 19 |
| 3 | Article Reading | 10 |
| 4 | Home & Navigation | 8 |
| 5 | Search | 7 |
| 6 | Lists | 5 |
| 7 | Settings | 7 |
| **Total** | | **67** |

---

## Deferred Tests (Post-MVP)

These tests are deferred due to complexity or flakiness risk:

- Email change with verification
- Password change with current password validation
- Handle change with uniqueness check
- Custom list creation/management
- Article tagging
- Actual website crawling end-to-end (integration test, not E2E)
- Mobile responsive behavior
- Keyboard navigation
- Accessibility (a11y) compliance
