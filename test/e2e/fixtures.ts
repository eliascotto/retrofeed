import { test as base, expect } from '@playwright/test';

// Use the base test directly - database is managed externally
// Use `bin/rails db:seed` before running tests to ensure test user exists
export const test = base;

// Re-export expect for convenience
export { expect };

// Test user credentials from fixtures
export const TEST_USER = {
  email: 'admin@retrofeed.com',
  password: 'password123',
  handle: 'admin',
};

// Helper to login a user
export async function login(page: import('@playwright/test').Page, email = TEST_USER.email, password = TEST_USER.password) {
  await page.goto('/login');
  await page.waitForLoadState('networkidle');
  await page.fill('input[name="email"]', email);
  await page.fill('input[name="password"]', password);
  await page.click('button[type="submit"]');
  await page.waitForURL('/');
}

// Helper to logout
export async function logout(page: import('@playwright/test').Page) {
  // Open the user menu and click logout
  await page.click('[data-testid="user-menu"]');
  await page.click('a[href*="logout"]');
  await page.waitForURL('/login');
}
