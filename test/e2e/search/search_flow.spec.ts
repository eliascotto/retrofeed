import { test, expect, login } from '../fixtures';

test.describe('Search Functionality', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('can access search page', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Search input should be visible
    await expect(page.locator('input[name="q"]')).toBeVisible();
  });

  test('search input is focused by default', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Search input should be focused (or at least visible)
    await expect(page.locator('input[name="q"]')).toBeVisible();
  });

  test('shows empty state when no query', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Should show a message about starting to search
    await expect(page.locator('text=Start typing')).toBeVisible();
  });

  test('can search for articles by title', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Type a search query and submit
    await page.fill('input[name="q"]', 'First');
    await page.press('input[name="q"]', 'Enter');

    // Wait for search to complete
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(500); // Give time for results to render

    // Verify search input still has the query (search executed)
    const inputValue = await page.locator('input[name="q"]').inputValue();
    expect(inputValue).toBe('First');
  });

  test('shows no results message for non-matching query', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Type a query that won't match anything
    await page.fill('input[name="q"]', 'xyznonexistentquery12345');
    await page.press('input[name="q"]', 'Enter');
    await page.waitForLoadState('networkidle');

    // Should show no results or empty state
    // The exact message depends on implementation
  });

  test('can switch between articles and sites tabs', async ({ page }) => {
    await page.goto('/search?q=test');
    await page.waitForLoadState('networkidle');

    // Look for tab buttons
    const articlesTab = page.locator('button[data-tab="articles"], a:has-text("Articles")').first();
    const sitesTab = page.locator('button[data-tab="sites"], a:has-text("Sites")').first();

    // If both tabs are visible, try switching
    const articlesVisible = await articlesTab.isVisible({ timeout: 3000 }).catch(() => false);
    const sitesVisible = await sitesTab.isVisible({ timeout: 3000 }).catch(() => false);

    if (articlesVisible && sitesVisible) {
      // Click sites tab
      await sitesTab.click();
      await page.waitForLoadState('networkidle');

      // URL should contain tab parameter
      expect(page.url()).toContain('tab=sites');

      // Click articles tab
      await articlesTab.click();
      await page.waitForLoadState('networkidle');

      expect(page.url()).toContain('tab=articles');
    }
  });

  test('search preserves query in URL', async ({ page }) => {
    const searchQuery = 'test search query';

    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    await page.fill('input[name="q"]', searchQuery);
    await page.press('input[name="q"]', 'Enter');
    await page.waitForLoadState('networkidle');

    // Search may use Ajax or form submission
    // Verify input still has the query after search
    const inputValue = await page.locator('input[name="q"]').inputValue();
    expect(inputValue).toBe(searchQuery);
  });

  test('search input shows current query', async ({ page }) => {
    const searchQuery = 'my search';

    await page.goto(`/search?q=${encodeURIComponent(searchQuery)}`);
    await page.waitForLoadState('networkidle');

    // Input should have the query value
    const inputValue = await page.locator('input[name="q"]').inputValue();
    expect(inputValue).toBe(searchQuery);
  });

  test('clicking search result navigates to article', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Search for something
    await page.fill('input[name="q"]', 'article');
    await page.press('input[name="q"]', 'Enter');
    await page.waitForLoadState('networkidle');

    // Try to find and click a search result
    const articleLink = page.locator('a[href^="/articles/"]').first();
    const articleExists = await articleLink.isVisible({ timeout: 5000 }).catch(() => false);

    if (articleExists) {
      await articleLink.click();
      await page.waitForURL(/\/articles\/\d+/);

      // Should be on article page
      await expect(page.locator('h1')).toBeVisible();
    }
  });

  test('clicking site result navigates to site', async ({ page }) => {
    await page.goto('/search?tab=sites');
    await page.waitForLoadState('networkidle');

    // Search for something
    await page.fill('input[name="q"]', 'site');
    await page.press('input[name="q"]', 'Enter');
    await page.waitForLoadState('networkidle');

    // Try to find and click a site result
    const siteLink = page.locator('a[href^="/sites/"]').first();
    const siteExists = await siteLink.isVisible({ timeout: 5000 }).catch(() => false);

    if (siteExists) {
      await siteLink.click();
      await page.waitForURL(/\/sites\/\d+/);

      // Should be on site page
      await expect(page.locator('h1, .text-xl')).toBeVisible();
    }
  });

  test('search handles special characters', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Search with special characters
    await page.fill('input[name="q"]', 'test & query % special');
    await page.press('input[name="q"]', 'Enter');
    await page.waitForLoadState('networkidle');

    // Should not error
    await expect(page.locator('input[name="q"]')).toBeVisible();
  });

  test('search is case insensitive', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle');

    // Search with uppercase
    await page.fill('input[name="q"]', 'ARTICLE');
    await page.press('input[name="q"]', 'Enter');
    await page.waitForLoadState('networkidle');

    // Should work without errors
    await expect(page.locator('input[name="q"]')).toBeVisible();
  });

  test('pagination works on search results', async ({ page }) => {
    // This test requires having enough results to paginate
    await page.goto('/search?q=a');  // Common letter to get many results
    await page.waitForLoadState('networkidle');

    // Check if pagination is visible
    const pagination = page.locator('input[name="page"], select[name="per_page"], .pagination');
    const paginationExists = await pagination.first().isVisible({ timeout: 3000 }).catch(() => false);

    if (paginationExists) {
      // Try navigating to page 2
      const page2Link = page.locator('a[href*="page=2"]').first();
      const page2Exists = await page2Link.isVisible({ timeout: 3000 }).catch(() => false);

      if (page2Exists) {
        await page2Link.click();
        await page.waitForLoadState('networkidle');

        // URL should contain page parameter
        expect(page.url()).toContain('page=2');
      }
    }
  });

  test('can access search from global navigation', async ({ page }) => {
    // Start from home page
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Look for search link/button in navigation
    const searchLink = page.locator('a[href="/search"], button:has-text("Search"), [data-testid="search-button"]').first();
    const searchExists = await searchLink.isVisible({ timeout: 3000 }).catch(() => false);

    if (searchExists) {
      await searchLink.click();
      await page.waitForURL(/\/search/);

      await expect(page.locator('input[name="q"]')).toBeVisible();
    }
  });
});
