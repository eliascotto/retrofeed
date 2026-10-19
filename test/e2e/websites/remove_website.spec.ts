import { test, expect, login } from '../fixtures';

test.describe('Remove Website', () => {
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

  // Helper to add a site via UI
  async function addSiteViaUI(page: import('@playwright/test').Page, url: string) {
    await openAddSiteModal(page);
    await page.fill('input[name="url"]', url);
    await clickModalSubmit(page);
    await expect(page.locator('#add-site-modal')).not.toBeVisible({ timeout: 10000 });
    await page.waitForTimeout(3000);
  }

  // 2.15 Unsubscribe from website
  test('2.15 - unsubscribe from website removes it from sites list', async ({ page }) => {
    await page.goto('/sites');
    await page.waitForLoadState('networkidle');

    // Check if there are sites - if none, try adding one via UI
    let noSites = await page.locator('text=No sites yet').isVisible();
    if (noSites) {
      await addSiteViaUI(page, 'https://overreacted.io/');
      await page.goto('/sites');
      await page.waitForLoadState('networkidle');
      noSites = await page.locator('text=No sites yet').isVisible();
    }

    // Skip if still no sites
    if (noSites) {
      test.skip();
      return;
    }

    // Wait for sites list to be visible
    await expect(page.locator('#sites-list')).toBeVisible();

    // Count sites before removal
    const sitesCountBefore = await page.locator('#sites-list > div[data-website-id]').count();

    // Get the first site
    const firstSite = page.locator('#sites-list > div[data-website-id]').first();

    // Click the dropdown menu (the details/summary element)
    await firstSite.locator('details summary').click();

    // Click the Remove link (opens confirmation modal)
    await page.click('a:has-text("Remove")');

    // Wait for the confirmation modal to appear
    await expect(page.locator('#remove-website-modal')).toBeVisible();

    // Click the red Remove button to confirm
    await page.click('#remove-website-modal button.btn-error');

    // Wait for the update
    await page.waitForTimeout(1000);

    // Verify the site count decreased or page shows empty state
    const sitesCountAfter = await page.locator('#sites-list > div[data-website-id]').count();
    const showsEmpty = await page.locator('text=No sites yet').isVisible();

    expect(sitesCountAfter < sitesCountBefore || showsEmpty).toBe(true);
  });

  // 2.17 Cancel unsubscribe - Tests that canceling the confirmation dialog keeps the site
  // This test runs after 2.15, so it uses any site that might exist
  test('2.17 - cancel unsubscribe keeps site subscribed', async ({ page }) => {
    await page.goto('/sites');
    await page.waitForLoadState('networkidle');

    // Check if there are sites - if none, add one via UI
    const noSites = await page.locator('text=No sites yet').isVisible();
    if (noSites) {
      await addSiteViaUI(page, 'https://overreacted.io/');
      await page.goto('/sites');
      await page.waitForLoadState('networkidle');
    }

    // Wait for sites list to be visible
    await expect(page.locator('#sites-list')).toBeVisible();

    // Count sites before
    const sitesCountBefore = await page.locator('#sites-list > div[data-website-id]').count();
    if (sitesCountBefore === 0) {
      test.skip();
      return;
    }

    // Get the first site
    const firstSite = page.locator('#sites-list > div[data-website-id]').first();

    // Click the dropdown menu (the details/summary element)
    await firstSite.locator('details summary').click();

    // Click the Remove link (opens confirmation modal)
    await page.click('a:has-text("Remove")');

    // Wait for the confirmation modal to appear
    await expect(page.locator('#remove-website-modal')).toBeVisible();

    // Click the Cancel button instead of confirming
    await page.click('#remove-website-modal button.btn-ghost');

    // Modal should be closed
    await expect(page.locator('#remove-website-modal')).not.toBeVisible();

    // Verify the site count is unchanged
    const sitesCountAfter = await page.locator('#sites-list > div[data-website-id]').count();
    expect(sitesCountAfter).toBe(sitesCountBefore);
  });
});
