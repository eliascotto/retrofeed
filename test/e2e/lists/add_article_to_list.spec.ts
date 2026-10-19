import { test, expect, login } from '../fixtures';

test.describe('Add Article to List', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  // Helper to create a reading list
  async function createList(page: import('@playwright/test').Page, title: string) {
    await page.click('button:has-text("Create reading list")');
    await expect(page.locator('#create-list-modal')).toBeVisible();
    await page.fill('#create-list-modal input[name="title"]', title);

    // Click submit
    await page.click('#create-list-modal button[type="submit"]');

    // Wait for page reload
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // Verify the list appears in sidebar
    await expect(page.locator(`a:has-text("${title}")`)).toBeVisible({ timeout: 10000 });
  }

  // Helper to open article dropdown menu
  async function openArticleMenu(page: import('@playwright/test').Page) {
    // Hover over the first article item to show the dropdown
    const articleItem = page.locator('[class*="group"]').first();
    await articleItem.hover();
    // Click the dropdown trigger (ellipsis button)
    const dropdownTrigger = articleItem.locator('.dropdown [role="button"]');
    await dropdownTrigger.click();
    // Wait for dropdown menu with "Add to list" to be visible
    await expect(page.locator('.dropdown-content:has-text("Add to list")')).toBeVisible();
  }

  test('modal opens when clicking "Add to list" menu option', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Open article menu and click "Add to list"
    await openArticleMenu(page);
    await page.click('text=Add to list');

    // Modal should be visible
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Search input should be focused
    await expect(page.locator('#add-to-list-search-input')).toBeFocused();
  });

  test('modal can be closed with Escape key', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Press Escape to close
    await page.keyboard.press('Escape');
    await expect(page.locator('#add-to-list-modal')).not.toBeVisible();
  });

  test('modal can be closed with close button', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Click close button
    await page.click('#add-to-list-modal button.btn-circle');
    await expect(page.locator('#add-to-list-modal')).not.toBeVisible();
  });

  test('shows existing lists and allows filtering', async ({ page }) => {
    const listTitle = `Filter Test List ${Date.now()}`;

    // First create a list
    await page.goto('/');
    await createList(page, listTitle);

    // Now open the add to list modal
    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // The list should be visible
    await expect(page.locator(`#add-to-list-modal:has-text("${listTitle}")`)).toBeVisible();

    // Type to filter
    await page.fill('#add-to-list-search-input', 'Filter Test');
    await expect(page.locator(`#add-to-list-modal:has-text("${listTitle}")`)).toBeVisible();

    // Type non-matching text - should show create option instead of empty state
    await page.fill('#add-to-list-search-input', 'ZZZZNONEXISTENT');
    // When typing a non-matching name, "Enter to create" option should appear
    await expect(page.locator('#add-to-list-modal:has-text("Enter to create")')).toBeVisible();
  });

  test('keyboard navigation works with arrow keys', async ({ page }) => {
    const listTitle1 = `Nav Test A ${Date.now()}`;
    const listTitle2 = `Nav Test B ${Date.now()}`;

    // Create two lists
    await page.goto('/');
    await createList(page, listTitle1);
    await createList(page, listTitle2);

    // Open the modal
    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // First item should be selected by default (has bg-base-200 class)
    const firstItem = page.locator('#add-to-list-modal [data-index="0"]');
    await expect(firstItem).toHaveClass(/bg-base-200/);

    // Press down arrow
    await page.keyboard.press('ArrowDown');

    // Second item should now be selected
    const secondItem = page.locator('#add-to-list-modal [data-index="1"]');
    await expect(secondItem).toHaveClass(/bg-base-200/);

    // Press up arrow
    await page.keyboard.press('ArrowUp');

    // First item should be selected again
    await expect(firstItem).toHaveClass(/bg-base-200/);
  });

  test('shows "Enter to create" option when typing new list name', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Type a unique list name that doesn't exist
    const uniqueListName = `Brand New List ${Date.now()}`;
    await page.fill('#add-to-list-search-input', uniqueListName);

    // Should show "Enter to create" badge
    await expect(page.locator('#add-to-list-modal:has-text("Enter to create")')).toBeVisible();
  });

  test('creates new list and adds article when selecting create option', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Type a unique list name
    const uniqueListName = `Created List ${Date.now()}`;
    await page.fill('#add-to-list-search-input', uniqueListName);

    // Press Enter to create and add
    await page.keyboard.press('Enter');

    // Wait for page reload (the controller reloads after creating)
    await page.waitForLoadState('networkidle');

    // The new list should appear in the sidebar
    await expect(page.locator(`a:has-text("${uniqueListName}")`)).toBeVisible({ timeout: 10000 });
  });

  test('adds article to existing list when selecting it', async ({ page }) => {
    const listTitle = `Add Article Test ${Date.now()}`;

    // Create a list first
    await page.goto('/');
    await createList(page, listTitle);

    // Open add to list modal
    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Click on the list to add the article
    await page.click(`#add-to-list-modal >> text="${listTitle}"`);

    // Modal should close
    await expect(page.locator('#add-to-list-modal')).not.toBeVisible({ timeout: 5000 });

    // Navigate to the list to verify the article was added
    await page.click(`a:has-text("${listTitle}")`);
    await page.waitForURL(/\/lists\//);

    // The page should show the list with articles (check for "article" text in count)
    await expect(page.locator('main:has-text("article")')).toBeVisible({ timeout: 5000 });
  });

  test('can select list with Enter key after navigating', async ({ page }) => {
    const listTitle = `Enter Select Test ${Date.now()}`;

    // Create a list first
    await page.goto('/');
    await createList(page, listTitle);

    // Open add to list modal
    await openArticleMenu(page);
    await page.click('text=Add to list');
    await expect(page.locator('#add-to-list-modal')).toBeVisible();

    // Filter with exact name to avoid "create new" option
    await page.fill('#add-to-list-search-input', listTitle);

    // Press Enter to select the list
    await page.keyboard.press('Enter');

    // Modal should close
    await expect(page.locator('#add-to-list-modal')).not.toBeVisible({ timeout: 5000 });
  });
});
