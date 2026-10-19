import { defineConfig, devices } from '@playwright/test';

const port = process.env.E2E_PORT || '3001';

export default defineConfig({
  testDir: './test/e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // Run your local dev server before starting the tests
  // Note: Set PLAYWRIGHT_START_SERVER=1 to start the server automatically
  // Prefer using `bin/rails test:e2e` which handles server startup properly
  webServer: process.env.PLAYWRIGHT_START_SERVER ? {
    command: `RAILS_ENV=test bin/rails server -b 0.0.0.0 -p ${port}`,
    url: `http://retrofeed.localhost:${port}`,
    reuseExistingServer: true,
    timeout: 120 * 1000,
  } : undefined,
});
