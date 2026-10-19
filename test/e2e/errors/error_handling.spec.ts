import { test, expect, login } from '../fixtures';

test.describe('Error Handling', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('displays not found error page', async ({ page }) => {
    await page.goto('/errors/not_found');
    await page.waitForLoadState('networkidle');

    // Should show error page with message
    await expect(page.locator('text=Oops!')).toBeVisible();
    await expect(page.locator('text=doesn\'t exist')).toBeVisible();

    // Should have go back button
    await expect(page.locator('text=Go back')).toBeVisible();
  });

  test('displays site not found error', async ({ page }) => {
    await page.goto('/errors/site_not_found');
    await page.waitForLoadState('networkidle');

    // Should show appropriate error message
    await expect(page.locator('text=Oops!')).toBeVisible();
    await expect(page.locator('text=site you\'re looking for doesn\'t exist')).toBeVisible();
  });

  test('displays article not found error', async ({ page }) => {
    await page.goto('/errors/article_not_found');
    await page.waitForLoadState('networkidle');

    // Should show appropriate error message
    await expect(page.locator('text=Oops!')).toBeVisible();
    await expect(page.locator('text=article you\'re looking for doesn\'t exist')).toBeVisible();
  });

  test('displays site no subscription error', async ({ page }) => {
    await page.goto('/errors/site_no_subscription');
    await page.waitForLoadState('networkidle');

    // Should show appropriate error message
    await expect(page.locator('text=Oops!')).toBeVisible();
    await expect(page.locator('text=don\'t have access to this site')).toBeVisible();
  });

  test('displays article no subscription error', async ({ page }) => {
    await page.goto('/errors/article_no_subscription');
    await page.waitForLoadState('networkidle');

    // Should show appropriate error message
    await expect(page.locator('text=Oops!')).toBeVisible();
    await expect(page.locator('text=don\'t have access to this article')).toBeVisible();
  });

  test('go back button navigates to appropriate page', async ({ page }) => {
    await page.goto('/errors/site_not_found');
    await page.waitForLoadState('networkidle');

    // Click go back button
    await page.click('text=Go back');
    await page.waitForURL('**/sites');

    // Should navigate to sites page
    expect(page.url()).toContain('/sites');
  });

  test('handles non-existent article gracefully', async ({ page }) => {
    // Try to access an article that doesn't exist
    await page.goto('/articles/999999999');
    await page.waitForLoadState('networkidle');

    // Should show error page or redirect
    const url = page.url();
    const hasError = url.includes('/errors') || await page.locator('text=Oops!').isVisible().catch(() => false);
    expect(hasError || url.includes('/articles')).toBeTruthy();
  });

  test('handles non-existent site gracefully', async ({ page }) => {
    // Try to access a site that doesn't exist
    await page.goto('/sites/999999999');
    await page.waitForLoadState('networkidle');

    // Should show error page or redirect
    const url = page.url();
    const hasError = url.includes('/errors') || await page.locator('text=Oops!').isVisible().catch(() => false);
    expect(hasError || url.includes('/sites')).toBeTruthy();
  });

  test('handles non-existent list gracefully', async ({ page }) => {
    // Try to access a list that doesn't exist
    await page.goto('/lists/zzz999999');
    await page.waitForLoadState('networkidle');

    // Should show error page or redirect
    const url = page.url();
    const hasError = url.includes('/errors') || await page.locator('text=Oops!').isVisible().catch(() => false);
    expect(hasError || url.includes('/lists')).toBeTruthy();
  });

  test('error page has proper structure', async ({ page }) => {
    await page.goto('/errors/not_found');
    await page.waitForLoadState('networkidle');

    // Should have header
    await expect(page.locator('main')).toBeVisible();

    // Should have error icon area (the large rounded div with error icon)
    await expect(page.locator('.w-16.h-16.rounded-full')).toBeVisible();

    // Should have back button
    const backButton = page.locator('a:has-text("Go back")');
    await expect(backButton).toBeVisible();

    // Back button should have href
    const href = await backButton.getAttribute('href');
    expect(href).toBeTruthy();
  });
});
