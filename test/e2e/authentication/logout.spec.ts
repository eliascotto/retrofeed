import { test, expect, TEST_USER, login } from '../fixtures';

test.describe('Logout', () => {
  // 1.4 Logout
  test('1.4 - logout clears session and redirects to login', async ({ page }) => {
    // First login
    await login(page);

    // Verify we're logged in
    await expect(page).toHaveURL('/');

    // Open the user menu dropdown (click the visible dropdown trigger in the sidebar)
    // On desktop, the user menu is in the sidebar at the bottom
    const userMenuTrigger = page.locator('aside .dropdown[class*="dropdown-top"] [role="button"]').first();
    await userMenuTrigger.click();

    // Click the visible logout link (from the dropdown that's now open)
    await page.click('a[href*="logout"]:visible');

    // Should redirect to login page
    await expect(page).toHaveURL('/login');

    // Should show success message
    await expect(page.locator('.alert-success')).toContainText('Logged out successfully');

    // Verify session is cleared by trying to access protected page
    await page.goto('/sites');
    await expect(page).toHaveURL('/login');
  });
});
