import { test, expect, login } from '../fixtures';

test.describe('Create Reading List', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  // Helper to open the create list modal
  async function openCreateListModal(page: import('@playwright/test').Page) {
    await page.goto('/');

    // Click the "Create reading list" button in the right sidebar
    await page.click('button:has-text("Create reading list")');
    await expect(page.locator('#create-list-modal')).toBeVisible();
  }

  // Helper to get the submit button
  function getSubmitButton(page: import('@playwright/test').Page) {
    return page.locator('#create-list-modal [data-create-list-modal-target="submitBtn"]');
  }

  test('modal opens when clicking create reading list button', async ({ page }) => {
    await openCreateListModal(page);

    // Verify modal title is visible
    await expect(page.locator('#create-list-modal h3')).toHaveText('Create Reading List');

    // Verify form fields are present
    await expect(page.locator('#create-list-modal input[name="title"]')).toBeVisible();
    await expect(page.locator('#create-list-modal textarea[name="description"]')).toBeVisible();

    // Verify buttons are present
    await expect(page.locator('#create-list-modal button:has-text("Cancel")')).toBeVisible();
    await expect(getSubmitButton(page)).toBeVisible();
  });

  test('create button is disabled when title is empty', async ({ page }) => {
    await openCreateListModal(page);

    // Submit button should be disabled initially
    await expect(getSubmitButton(page)).toBeDisabled();

    // Type a title
    await page.fill('#create-list-modal input[name="title"]', 'My List');
    await expect(getSubmitButton(page)).not.toBeDisabled();

    // Clear the title
    await page.fill('#create-list-modal input[name="title"]', '');
    await expect(getSubmitButton(page)).toBeDisabled();
  });

  test('successfully creates a reading list with title only', async ({ page }) => {
    await openCreateListModal(page);

    const listTitle = `Test List ${Date.now()}`;

    // Fill in the title
    await page.fill('#create-list-modal input[name="title"]', listTitle);

    // Click create
    await getSubmitButton(page).click();

    // Wait for page reload
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // List should appear in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).toBeVisible({ timeout: 10000 });
  });

  test('successfully creates a reading list with title and description', async ({ page }) => {
    await openCreateListModal(page);

    const listTitle = `Tech Articles ${Date.now()}`;
    const listDescription = 'Articles about programming and technology';

    // Fill in title and description
    await page.fill('#create-list-modal input[name="title"]', listTitle);
    await page.fill('#create-list-modal textarea[name="description"]', listDescription);

    // Click create
    await getSubmitButton(page).click();

    // Wait for page reload
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // List should appear in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).toBeVisible({ timeout: 10000 });
  });

  test('modal can be closed with cancel button', async ({ page }) => {
    await openCreateListModal(page);

    // Click cancel
    await page.click('#create-list-modal button:has-text("Cancel")');

    // Modal should close
    await expect(page.locator('#create-list-modal')).not.toBeVisible();
  });

  test('modal can be closed with X button', async ({ page }) => {
    await openCreateListModal(page);

    // Click the X button
    await page.click('#create-list-modal button.btn-circle');

    // Modal should close
    await expect(page.locator('#create-list-modal')).not.toBeVisible();
  });

  test('modal can be closed by pressing Escape', async ({ page }) => {
    await openCreateListModal(page);

    // Press Escape to close modal
    await page.keyboard.press('Escape');

    // Modal should close
    await expect(page.locator('#create-list-modal')).not.toBeVisible();
  });

  test('form resets when modal is reopened', async ({ page }) => {
    await openCreateListModal(page);

    // Fill in title
    await page.fill('#create-list-modal input[name="title"]', 'Some Title');
    await page.fill('#create-list-modal textarea[name="description"]', 'Some Description');

    // Close modal
    await page.click('#create-list-modal button:has-text("Cancel")');

    // Reopen modal
    await page.click('button:has-text("Create reading list")');
    await expect(page.locator('#create-list-modal')).toBeVisible();

    // Fields should be empty
    await expect(page.locator('#create-list-modal input[name="title"]')).toHaveValue('');
    await expect(page.locator('#create-list-modal textarea[name="description"]')).toHaveValue('');
  });

  test('created list appears in sidebar and is clickable', async ({ page }) => {
    await openCreateListModal(page);

    const listTitle = `Clickable List ${Date.now()}`;

    // Create the list
    await page.fill('#create-list-modal input[name="title"]', listTitle);
    await getSubmitButton(page).click();

    // Wait for page reload
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // Wait for list to appear in sidebar
    const listLink = page.locator(`a:has-text("${listTitle}")`);
    await expect(listLink).toBeVisible({ timeout: 10000 });

    // Click the list
    await listLink.click();

    // Should navigate to the list page
    await page.waitForURL(/\/lists\//);

    // Page should show the list title in the heading
    await expect(page.locator(`h1:has-text("${listTitle}")`)).toBeVisible();
  });

  test('multiple lists can be created', async ({ page }) => {
    const list1Title = `First List ${Date.now()}`;
    const list2Title = `Second List ${Date.now()}`;

    // Create first list
    await openCreateListModal(page);
    await page.fill('#create-list-modal input[name="title"]', list1Title);
    await getSubmitButton(page).click();
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // Wait for first list to appear
    await expect(page.locator(`a:has-text("${list1Title}")`)).toBeVisible({ timeout: 10000 });

    // Create second list
    await page.click('button:has-text("Create reading list")');
    await expect(page.locator('#create-list-modal')).toBeVisible();
    await page.fill('#create-list-modal input[name="title"]', list2Title);
    await getSubmitButton(page).click();
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // Both lists should be visible in sidebar
    await expect(page.locator(`a:has-text("${list1Title}")`)).toBeVisible({ timeout: 10000 });
    await expect(page.locator(`a:has-text("${list2Title}")`)).toBeVisible();
  });
});
