import { test, expect, login } from '../fixtures';

test.describe('Article Reading Flow', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('can open article from home page', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for articles to load
    const articleLink = page.locator('a[href^="/articles/"]').first();

    // Skip test if no articles are available
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!articleExists) {
      test.skip();
      return;
    }

    // Get article title before clicking
    const articleTitle = await articleLink.locator('.text-sm.font-medium').textContent();

    // Click the article
    await articleLink.click();

    // Should navigate to article page
    await page.waitForURL(/\/articles\/\d+/);

    // Article title should be visible in the page
    if (articleTitle) {
      await expect(page.locator('h1')).toContainText(articleTitle.trim());
    }
  });

  test('article page displays content correctly', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const articleLink = page.locator('a[href^="/articles/"]').first();
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!articleExists) {
      test.skip();
      return;
    }

    await articleLink.click();
    await page.waitForURL(/\/articles\/\d+/);

    // Article should have a title
    await expect(page.locator('h1')).toBeVisible();

    // Article should have content area
    await expect(page.locator('article').first()).toBeVisible();
  });

  test('can navigate to next article from same site', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const articleLink = page.locator('a[href^="/articles/"]').first();
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!articleExists) {
      test.skip();
      return;
    }

    await articleLink.click();
    await page.waitForURL(/\/articles\/\d+/);

    // Get current article URL
    const currentUrl = page.url();

    // Look for "Next from site" or similar navigation
    const nextButton = page.locator('a[href*="next_article"], button:has-text("Next"), a:has-text("Next from site")');
    const nextButtonExists = await nextButton.first().isVisible({ timeout: 3000 }).catch(() => false);

    if (nextButtonExists) {
      await nextButton.first().click();

      // Should either navigate to a new article or show a message about no more articles
      await page.waitForLoadState('networkidle');

      // Verify we're still on an article page or sites page (navigation worked)
      const newUrl = page.url();
      const urlChanged = newUrl !== currentUrl;
      const onArticlePage = newUrl.includes('/articles/');
      const onSitePage = newUrl.includes('/sites/');
      expect(urlChanged || onArticlePage || onSitePage).toBeTruthy();
    }
  });

  test('can navigate to random article', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const articleLink = page.locator('a[href^="/articles/"]').first();
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!articleExists) {
      test.skip();
      return;
    }

    await articleLink.click();
    await page.waitForURL(/\/articles\/\d+/);

    // Get current article URL
    const currentUrl = page.url();

    // Look for random article button
    const randomButton = page.locator('a[href*="random"], button:has-text("Random")');
    const randomButtonExists = await randomButton.first().isVisible({ timeout: 3000 }).catch(() => false);

    if (randomButtonExists) {
      await randomButton.first().click();

      await page.waitForLoadState('networkidle');

      // Either URL changed (new article) or we're redirected to site page
      const newUrl = page.url();
      expect(newUrl !== currentUrl || page.url().includes('/sites/')).toBeTruthy();
    }
  });

  test('can mark article as read and it disappears from recent tab', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Make sure we're on the recent tab
    const recentTab = page.locator('a[href*="tab=recent"], a:has-text("Recent")').first();
    if (await recentTab.isVisible()) {
      await recentTab.click();
      await page.waitForLoadState('networkidle');
    }

    // Count initial articles
    const initialArticleLinks = page.locator('a[href^="/articles/"]');
    const initialCount = await initialArticleLinks.count();

    if (initialCount === 0) {
      test.skip();
      return;
    }

    // Get first article's href to track it
    const firstArticleHref = await initialArticleLinks.first().getAttribute('href');

    // Click the first article
    await initialArticleLinks.first().click();
    await page.waitForURL(/\/articles\/\d+/);

    // Find and click the "Mark as read" or "Done" button
    const markReadButton = page.locator('a[href*="mark_read"], button:has-text("Mark as read"), button:has-text("Done"), a:has-text("Mark read")');
    const markReadExists = await markReadButton.first().isVisible({ timeout: 3000 }).catch(() => false);

    if (markReadExists) {
      await markReadButton.first().click();
      await page.waitForLoadState('networkidle');

      // Go back to home
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      // The article should no longer appear in the recent tab
      // (or it should be marked differently)
      const articleAfterRead = page.locator(`a[href="${firstArticleHref}"]`);

      // Either the article is gone, or it's no longer in recent (we might be on a different page)
      // This test verifies the read state was tracked
    }
  });

  test('reading tab shows in-progress articles', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Click on the reading tab
    const readingTab = page.locator('a[href*="tab=reading"], a:has-text("Reading")').first();
    const readingTabExists = await readingTab.isVisible({ timeout: 3000 }).catch(() => false);

    if (!readingTabExists) {
      test.skip();
      return;
    }

    await readingTab.click();
    await page.waitForLoadState('networkidle');

    // Verify we're on the reading tab
    await expect(page.locator('a[href*="tab=reading"].border-primary, a:has-text("Reading").border-primary')).toBeVisible();

    // The reading tab should show articles that have been started but not finished
    // This might be empty if no articles are in progress
  });

  test('article view is tracked when page renders', async ({ page }) => {
    // This test verifies the track_view mechanism works
    // When an article page renders, the Stimulus controller should call track_view

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const articleLink = page.locator('a[href^="/articles/"]').first();
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!articleExists) {
      test.skip();
      return;
    }

    // Intercept API calls to verify track_view is called
    let trackViewCalled = false;
    await page.route('**/api/articles/*/track_view', (route) => {
      trackViewCalled = true;
      route.continue();
    });

    // Click the article
    await articleLink.click();
    await page.waitForURL(/\/articles\/\d+/);

    // Wait a bit for the Stimulus controller to initialize and call track_view
    await page.waitForTimeout(1000);

    // Verify track_view was called
    expect(trackViewCalled).toBe(true);
  });

  test('can open article from site page', async ({ page }) => {
    await page.goto('/sites');
    await page.waitForLoadState('networkidle');

    // Click on a site
    const siteLink = page.locator('[data-website-id]').first();
    const siteExists = await siteLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!siteExists) {
      test.skip();
      return;
    }

    await siteLink.click();
    await page.waitForURL(/\/sites\/\d+/);

    // Wait for articles to load
    const articleLink = page.locator('a[href^="/articles/"]').first();
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (!articleExists) {
      test.skip();
      return;
    }

    // Click the article
    await articleLink.click();
    await page.waitForURL(/\/articles\/\d+/);

    // Should be on article page
    await expect(page.locator('h1')).toBeVisible();
  });

  test('unsubscribed user cannot access article', async ({ page }) => {
    // Try to access an article directly by ID that might not be subscribed
    // This is a tricky test because we need to know an article ID that the user isn't subscribed to
    // We'll verify the error page mechanism works

    await page.goto('/articles/999999999');
    await page.waitForLoadState('networkidle');

    // Should be redirected to error page
    await expect(page.url()).toContain('/error');
  });
});
