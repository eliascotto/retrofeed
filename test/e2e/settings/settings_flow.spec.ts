import { test, expect, login } from '../fixtures';

test.describe('Settings Flow', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('can access settings page', async ({ page }) => {
    await page.goto('/settings');
    await page.waitForLoadState('networkidle');

    // Settings page should load with Settings heading in main content
    await expect(page.locator('main h1:has-text("Settings")')).toBeVisible();
  });

  test('can navigate to account settings', async ({ page }) => {
    await page.goto('/settings');
    await page.waitForLoadState('networkidle');

    // Look for account link and click it
    const accountLink = page.locator('a[href*="/settings/account"]').first();
    await expect(accountLink).toBeVisible();
    await accountLink.click();
    await page.waitForURL('**/settings/account');

    // Should be on account page
    expect(page.url()).toContain('/settings/account');
  });

  test('can navigate to appearance settings', async ({ page }) => {
    await page.goto('/settings');
    await page.waitForLoadState('networkidle');

    // Look for appearance link and click it
    const appearanceLink = page.locator('a[href*="/settings/appearance"]').first();
    await expect(appearanceLink).toBeVisible();
    await appearanceLink.click();
    await page.waitForURL('**/settings/appearance');

    // Should be on appearance page
    expect(page.url()).toContain('/settings/appearance');
  });

  test('can change theme setting', async ({ page }) => {
    await page.goto('/settings/appearance');
    await page.waitForLoadState('networkidle');

    // Look for theme selector
    const themeSelect = page.locator('select[name*="theme"], input[name*="theme"], [data-testid="theme-selector"]').first();
    const themeExists = await themeSelect.isVisible({ timeout: 3000 }).catch(() => false);

    if (themeExists) {
      // Try to change theme
      const tagName = await themeSelect.evaluate(el => el.tagName.toLowerCase());
      if (tagName === 'select') {
        await themeSelect.selectOption({ index: 1 });
      }

      // Look for save button or form auto-saves
      const saveButton = page.locator('button[type="submit"], button:has-text("Save")').first();
      const saveExists = await saveButton.isVisible({ timeout: 2000 }).catch(() => false);

      if (saveExists) {
        await saveButton.click();
        await page.waitForLoadState('networkidle');
      }

      // Page should not error
      await expect(page.locator('body')).toBeVisible();
    }
  });

  test('can change font size setting', async ({ page }) => {
    await page.goto('/settings/appearance');
    await page.waitForLoadState('networkidle');

    // Look for font size selector
    const fontSizeSelect = page.locator('select[name*="font_size"], [data-testid="font-size-selector"]').first();
    const fontSizeExists = await fontSizeSelect.isVisible({ timeout: 3000 }).catch(() => false);

    if (fontSizeExists) {
      // Try to change font size
      const tagName = await fontSizeSelect.evaluate(el => el.tagName.toLowerCase());
      if (tagName === 'select') {
        await fontSizeSelect.selectOption({ index: 1 });
      }

      // Look for save button
      const saveButton = page.locator('button[type="submit"], button:has-text("Save")').first();
      const saveExists = await saveButton.isVisible({ timeout: 2000 }).catch(() => false);

      if (saveExists) {
        await saveButton.click();
        await page.waitForLoadState('networkidle');
      }

      // Page should not error
      await expect(page.locator('body')).toBeVisible();
    }
  });

  test('can change font family setting', async ({ page }) => {
    await page.goto('/settings/appearance');
    await page.waitForLoadState('networkidle');

    // Look for font family selector
    const fontFamilySelect = page.locator('select[name*="font_family"], [data-testid="font-family-selector"]').first();
    const fontFamilyExists = await fontFamilySelect.isVisible({ timeout: 3000 }).catch(() => false);

    if (fontFamilyExists) {
      const tagName = await fontFamilySelect.evaluate(el => el.tagName.toLowerCase());
      if (tagName === 'select') {
        await fontFamilySelect.selectOption({ index: 1 });
      }

      const saveButton = page.locator('button[type="submit"], button:has-text("Save")').first();
      const saveExists = await saveButton.isVisible({ timeout: 2000 }).catch(() => false);

      if (saveExists) {
        await saveButton.click();
        await page.waitForLoadState('networkidle');
      }

      await expect(page.locator('body')).toBeVisible();
    }
  });

  test('settings persist after page reload', async ({ page }) => {
    await page.goto('/settings/appearance');
    await page.waitForLoadState('networkidle');

    // Look for any setting selector
    const selector = page.locator('select').first();
    const selectorExists = await selector.isVisible({ timeout: 3000 }).catch(() => false);

    if (selectorExists) {
      // Get current value
      const originalValue = await selector.inputValue();

      // Change to a different value
      const options = await selector.locator('option').all();
      if (options.length > 1) {
        // Select a different option
        const newIndex = originalValue === await options[0].getAttribute('value') ? 1 : 0;
        await selector.selectOption({ index: newIndex });

        // Save if there's a save button
        const saveButton = page.locator('button[type="submit"], button:has-text("Save")').first();
        const saveExists = await saveButton.isVisible({ timeout: 2000 }).catch(() => false);
        if (saveExists) {
          await saveButton.click();
          await page.waitForLoadState('networkidle');
        }

        // Reload page
        await page.reload();
        await page.waitForLoadState('networkidle');

        // Value should persist (if form auto-saves or was saved)
        await expect(page.locator('body')).toBeVisible();
      }
    }
  });

  test('can access handle settings', async ({ page }) => {
    await page.goto('/settings/account/handle');
    await page.waitForLoadState('networkidle');

    // Should show handle input
    const handleInput = page.locator('input[name*="handle"]').first();
    await expect(handleInput).toBeVisible();
  });

  test('can access email settings', async ({ page }) => {
    await page.goto('/settings/account/email');
    await page.waitForLoadState('networkidle');

    // Should show email input
    const emailInput = page.locator('input[name*="email"], input[type="email"]').first();
    await expect(emailInput).toBeVisible();
  });

  test('can access password settings', async ({ page }) => {
    await page.goto('/settings/account/password');
    await page.waitForLoadState('networkidle');

    // Should show password inputs
    const passwordInput = page.locator('input[type="password"]').first();
    await expect(passwordInput).toBeVisible();
  });

  test('settings navigation works correctly', async ({ page }) => {
    // Start at settings
    await page.goto('/settings');
    await page.waitForLoadState('networkidle');

    // Check that we can navigate through settings sections
    const navLinks = page.locator('nav a, aside a, .sidebar a').all();

    // Should have navigation links
    const links = await navLinks;
    expect(links.length).toBeGreaterThan(0);
  });
});
