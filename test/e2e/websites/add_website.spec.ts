import { test, expect, login } from '../fixtures';

test.describe('Add Website', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  // Helper to open the add site modal
  async function openAddSiteModal(page: import('@playwright/test').Page) {
    await page.goto('/sites');

    await page.evaluate(() => window.dispatchEvent(new CustomEvent('modal:open')));
    await expect(page.locator('#add-site-modal')).toBeVisible();
  }

  // Helper to click the submit button inside the modal
  async function clickModalSubmit(page: import('@playwright/test').Page) {
    await page.click('#add-site-modal [data-add-site-modal-target="submitBtn"]');
  }

  // Helper to wait for website to appear in sites list
  async function waitForSiteInList(page: import('@playwright/test').Page, domain: string, timeout = 30000) {
    await page.goto('/sites');
    await expect(page.locator(`text=${domain}`)).toBeVisible({ timeout });
  }

  // Helper to wait for articles to be processed on site page
  async function waitForArticles(page: import('@playwright/test').Page, minArticles = 1, timeout = 120000) {
    // Wait for the articles list to have at least minArticles items
    const articlesSelector = '[data-article-list] > *';

    await expect(async () => {
      const count = await page.locator(articlesSelector).count();
      expect(count).toBeGreaterThanOrEqual(minArticles);
    }).toPass({ timeout });
  }

  // 2.1 Add website - validates URL format (browser validation)
  test('2.1 - add website without https:// shows browser validation', async ({ page }) => {
    await openAddSiteModal(page);
    await page.fill('input[name="url"]', 'example.org/blog');

    const urlInput = page.locator('input[name="url"]');
    const isInvalid = await urlInput.evaluate((el: HTMLInputElement) => !el.validity.valid);
    expect(isInvalid).toBe(true);
    await expect(page.locator('#add-site-modal')).toBeVisible();
  });

  // 2.2 Add website - empty URL
  test('2.2 - add website with empty URL shows browser validation', async ({ page }) => {
    await openAddSiteModal(page);
    await page.fill('input[name="url"]', '');

    const urlInput = page.locator('input[name="url"]');
    const isInvalid = await urlInput.evaluate((el: HTMLInputElement) => !el.validity.valid);
    expect(isInvalid).toBe(true);

    await clickModalSubmit(page);
    await expect(page.locator('#add-site-modal')).toBeVisible();
  });

  // 2.3 Add website - invalid URL format
  test('2.3 - add website with invalid URL format shows browser validation', async ({ page }) => {
    await openAddSiteModal(page);
    await page.fill('input[name="url"]', ':::invalid');

    const urlInput = page.locator('input[name="url"]');
    const isInvalid = await urlInput.evaluate((el: HTMLInputElement) => !el.validity.valid);
    expect(isInvalid).toBe(true);

    await clickModalSubmit(page);
    await expect(page.locator('#add-site-modal')).toBeVisible();
  });

  // 2.4 Add paulgraham.com and verify articles are processed
  // This is a critical test - it verifies the entire pipeline works
  test('2.4 - add paulgraham.com processes articles successfully', async ({ page }) => {
    // Record initial site count
    await page.goto('/sites');
    const initialSiteCount = await page.locator('[data-website-id]').count();

    // Add the website
    await openAddSiteModal(page);
    await page.fill('input[name="url"]', 'https://paulgraham.com/articles.html');
    await clickModalSubmit(page);

    // Modal should close (job enqueued)
    await expect(page.locator('#add-site-modal')).not.toBeVisible({ timeout: 10000 });

    // Wait for the website to appear in the sites list
    await page.waitForTimeout(2000); // Give job time to start
    await page.goto('/sites');

    // Wait for site count to increase
    await expect(async () => {
      await page.reload();
      const currentCount = await page.locator('[data-website-id]').count();
      expect(currentCount).toBeGreaterThan(initialSiteCount);
    }).toPass({ timeout: 30000 });

    // Find and click on the paulgraham.com site
    const siteLink = page.locator('[data-website-id]').filter({ hasText: 'paulgraham.com' });
    await expect(siteLink).toBeVisible({ timeout: 5000 });
    await siteLink.click();

    // Wait for the site page to load
    await page.waitForURL(/\/sites\/\d+/);

    // Wait for articles to be processed (this may take a while)
    // paulgraham.com has many articles, wait for at least 5
    await expect(async () => {
      await page.reload();
      const progressText = await page.locator('[data-progress-text]').textContent();
      // Progress text is like "0/123 articles" - extract the first number
      const match = progressText?.match(/(\d+)\/(\d+)/);
      if (match) {
        const processed = parseInt(match[1], 10);
        const total = parseInt(match[2], 10);
        expect(total).toBeGreaterThan(0); // Website should have articles
        expect(processed).toBeGreaterThanOrEqual(5); // At least 5 should be processed
      } else {
        throw new Error(`Could not parse progress text: ${progressText}`);
      }
    }).toPass({ timeout: 180000 }); // 3 minutes for processing
  });

  // 2.5 Add overreacted.io and verify articles are processed
  test('2.5 - add overreacted.io processes articles successfully', async ({ page }) => {
    await page.goto('/sites');
    const initialSiteCount = await page.locator('[data-website-id]').count();

    await openAddSiteModal(page);
    await page.fill('input[name="url"]', 'https://overreacted.io/');
    await clickModalSubmit(page);

    await expect(page.locator('#add-site-modal')).not.toBeVisible({ timeout: 10000 });

    // Wait for site to appear
    await page.waitForTimeout(2000);
    await page.goto('/sites');

    await expect(async () => {
      await page.reload();
      const currentCount = await page.locator('[data-website-id]').count();
      expect(currentCount).toBeGreaterThan(initialSiteCount);
    }).toPass({ timeout: 30000 });

    // Click on the site
    const siteLink = page.locator('[data-website-id]').filter({ hasText: 'overreacted.io' });
    await expect(siteLink).toBeVisible({ timeout: 5000 });
    await siteLink.click();

    await page.waitForURL(/\/sites\/\d+/);

    // Wait for articles to be processed
    await expect(async () => {
      await page.reload();
      const progressText = await page.locator('[data-progress-text]').textContent();
      const match = progressText?.match(/(\d+)\/(\d+)/);
      if (match) {
        const processed = parseInt(match[1], 10);
        const total = parseInt(match[2], 10);
        expect(total).toBeGreaterThan(0);
        expect(processed).toBeGreaterThanOrEqual(5);
      } else {
        throw new Error(`Could not parse progress text: ${progressText}`);
      }
    }).toPass({ timeout: 180000 });
  });

  // 2.6 Add mitchellh.com and verify articles are processed
  test('2.6 - add mitchellh.com processes articles successfully', async ({ page }) => {
    await page.goto('/sites');
    const initialSiteCount = await page.locator('[data-website-id]').count();

    await openAddSiteModal(page);
    await page.fill('input[name="url"]', 'https://mitchellh.com/writing');
    await clickModalSubmit(page);

    await expect(page.locator('#add-site-modal')).not.toBeVisible({ timeout: 10000 });

    // Wait for site to appear
    await page.waitForTimeout(2000);
    await page.goto('/sites');

    await expect(async () => {
      await page.reload();
      const currentCount = await page.locator('[data-website-id]').count();
      expect(currentCount).toBeGreaterThan(initialSiteCount);
    }).toPass({ timeout: 30000 });

    // Click on the site
    const siteLink = page.locator('[data-website-id]').filter({ hasText: 'mitchellh.com' });
    await expect(siteLink).toBeVisible({ timeout: 5000 });
    await siteLink.click();

    await page.waitForURL(/\/sites\/\d+/);

    // Wait for articles to be processed
    await expect(async () => {
      await page.reload();
      const progressText = await page.locator('[data-progress-text]').textContent();
      const match = progressText?.match(/(\d+)\/(\d+)/);
      if (match) {
        const processed = parseInt(match[1], 10);
        const total = parseInt(match[2], 10);
        expect(total).toBeGreaterThan(0);
        expect(processed).toBeGreaterThanOrEqual(3);
      } else {
        throw new Error(`Could not parse progress text: ${progressText}`);
      }
    }).toPass({ timeout: 180000 });
  });

  // 2.7 Add duplicate website shows warning toast
  // This test relies on paulgraham.com already being added by test 2.4
  test('2.7 - add duplicate website shows warning toast', async ({ page }) => {
    await page.goto('/sites');

    // Check if paulgraham.com is already in the list (from previous tests)
    // If not, add it first
    const siteExists = await page.locator('[data-website-id]').filter({ hasText: 'paulgraham.com' }).isVisible();
    if (!siteExists) {
      // Add paulgraham.com first
      await openAddSiteModal(page);
      await page.fill('input[name="url"]', 'https://paulgraham.com/articles.html');
      await clickModalSubmit(page);

      // Wait for the modal to close (job enqueued)
      await expect(page.locator('#add-site-modal')).not.toBeVisible({ timeout: 10000 });

      // Wait for website to appear in the list
      await expect(async () => {
        await page.reload();
        const siteLink = page.locator('[data-website-id]').filter({ hasText: 'paulgraham.com' });
        await expect(siteLink).toBeVisible();
      }).toPass({ timeout: 60000 });
    }

    // Now try to add paulgraham.com again (should show duplicate error)
    await openAddSiteModal(page);
    await page.fill('input[name="url"]', 'https://paulgraham.com/');
    await clickModalSubmit(page);

    // Modal should stay open with error message
    await expect(page.locator('#add-site-modal')).toBeVisible();

    // Error message should appear in the modal
    const errorMessage = page.locator('[data-add-site-modal-target="urlError"]');
    await expect(errorMessage).toBeVisible();
    await expect(errorMessage).toContainText('already subscribed to paulgraham.com');

    // Toast notification should appear with warning styling
    const toast = page.locator('.toast .alert-warning');
    await expect(toast).toBeVisible({ timeout: 5000 });
    await expect(toast).toContainText('already subscribed to paulgraham.com');
  });
});
