import { test, expect, TEST_USER } from '../fixtures';

test.describe('Login', () => {
  // 1.1 Login with valid credentials
  test('1.1 - login with valid credentials redirects to home', async ({ page }) => {
    await page.goto('/login');
    await page.waitForLoadState('networkidle');

    await page.fill('input[name="email"]', TEST_USER.email);
    await page.fill('input[name="password"]', TEST_USER.password);
    await page.click('button[type="submit"]');

    // Should redirect to home page
    await expect(page).toHaveURL('/');

    // Should show user content (the home page)
    await expect(page.locator('body')).not.toContainText('Please log in');
  });

  // 1.2 Login with invalid email
  test('1.2 - login with non-existent email shows error', async ({ page }) => {
    await page.goto('/login');
    await page.waitForLoadState('networkidle');

    await page.fill('input[name="email"]', 'nonexistent@example.com');
    await page.fill('input[name="password"]', 'somepassword');
    await page.click('button[type="submit"]');

    // Should stay on login page and show error
    await expect(page).toHaveURL('/login');
    await expect(page.locator('.alert-error')).toContainText('Invalid email or password');
  });

  // 1.3 Login with wrong password
  test('1.3 - login with wrong password shows error', async ({ page }) => {
    await page.goto('/login');
    await page.waitForLoadState('networkidle');

    await page.fill('input[name="email"]', TEST_USER.email);
    await page.fill('input[name="password"]', 'wrongpassword123');
    await page.click('button[type="submit"]');

    // Should stay on login page and show error
    await expect(page).toHaveURL('/login');
    await expect(page.locator('.alert-error')).toContainText('Invalid email or password');
  });

  // 1.5 Unauthenticated access to protected page
  test('1.5 - unauthenticated access to /sites redirects to login', async ({ page }) => {
    await page.goto('/sites');
    await page.waitForLoadState('networkidle');

    // Should redirect to login page
    await expect(page).toHaveURL('/login');
    await expect(page.locator('.alert-error')).toContainText('Please log in to continue');
  });
});
