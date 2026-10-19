import { test, expect, TEST_USER } from '../fixtures';

test.describe('Signup', () => {
  // Generate unique email for each test run to avoid conflicts
  const uniqueEmail = () => `newuser_${Date.now()}@example.com`;

  // 1.6 Signup - valid data creates account
  test('1.6 - signup with valid data creates account and redirects to confirmation', async ({ page }) => {
    await page.goto('/signup');

    await page.fill('input[name="email"]', uniqueEmail());
    await page.fill('input[name="password"]', 'validpassword123');
    await page.click('button[type="submit"]');

    // Should redirect to confirmation resend page
    await expect(page).toHaveURL('/confirmations/resend');
    await expect(page.locator('body')).toContainText('confirm');
  });

  // 1.7 Signup - invalid email
  test('1.7 - signup with invalid email shows validation error', async ({ page }) => {
    await page.goto('/signup');

    // The HTML5 email validation should prevent submission with invalid email
    // We need to check the input validity
    await page.fill('input[name="email"]', 'not-an-email');
    await page.fill('input[name="password"]', 'validpassword123');

    // Check if the email input is invalid
    const emailInput = page.locator('input[name="email"]');
    const isInvalid = await emailInput.evaluate((el: HTMLInputElement) => !el.validity.valid);
    expect(isInvalid).toBe(true);
  });

  // 1.8 Signup - short password
  test('1.8 - signup with short password shows validation error', async ({ page }) => {
    await page.goto('/signup');

    await page.fill('input[name="email"]', uniqueEmail());
    await page.fill('input[name="password"]', 'short');
    await page.click('button[type="submit"]');

    // Should stay on signup page and show error
    await expect(page).toHaveURL('/signup');
    await expect(page.locator('.alert-error')).toContainText('Password must be at least 8 characters');
  });

  // 1.9 Signup - duplicate email
  test('1.9 - signup with existing email shows error', async ({ page }) => {
    await page.goto('/signup');

    await page.fill('input[name="email"]', TEST_USER.email);
    await page.fill('input[name="password"]', 'validpassword123');
    await page.click('button[type="submit"]');

    // Should stay on signup page and show error
    await expect(page).toHaveURL('/signup');
    await expect(page.locator('.alert-error')).toContainText('already exists');
  });
});
