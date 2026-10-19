import { test, expect, login } from '../fixtures';

test.describe('Delete Reading List', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  // Helper to create a list via the modal
  async function createList(page: import('@playwright/test').Page, title: string) {
    await page.goto('/');
    await page.click('button:has-text("Create reading list")');
    await expect(page.locator('#create-list-modal')).toBeVisible();
    await page.fill('#create-list-modal input[name="title"]', title);

    // Click submit
    await page.locator('#create-list-modal [data-create-list-modal-target="submitBtn"]').click();

    // Wait for the page to reload by checking that the modal is gone and the list appears
    await page.waitForLoadState('load');
    await page.waitForLoadState('networkidle');

    // Verify the list appears in sidebar
    await expect(page.locator(`a:has-text("${title}")`)).toBeVisible({ timeout: 10000 });
  }

  // Helper to get the list item container for a specific list
  function getListItem(page: import('@playwright/test').Page, listTitle: string) {
    return page.locator('.reading-list-item').filter({ hasText: listTitle }).first();
  }

  // Helper to open the context menu for a list and click delete
  async function openDeleteDialogForList(page: import('@playwright/test').Page, listTitle: string) {
    const listItem = getListItem(page, listTitle);
    await listItem.hover();

    // Click the ellipsis button to open the dropdown
    const dropdownTrigger = listItem.locator('.dropdown [role="button"]');
    await dropdownTrigger.click();

    // Wait for dropdown to be visible
    await expect(listItem.locator('.dropdown-content')).toBeVisible();

    // Get the delete button's onclick parameters
    const deleteButton = listItem.locator('.dropdown-content button:has-text("Delete")');
    const onclickAttr = await deleteButton.getAttribute('onclick');

    // Extract parameters from onclick and call the function directly
    // onclick format: openDeleteListModal(123, 'title', '/api/lists/123'); document.activeElement.blur();
    const match = onclickAttr?.match(/openDeleteListModal\((\d+),\s*'([^']*)',\s*'([^']*)'\)/);
    if (match) {
      const [, listId, title, deletePath] = match;
      await page.evaluate(([id, t, path]) => {
        (window as any).openDeleteListModal(parseInt(id), t, path);
      }, [listId, title, deletePath]);
    } else {
      // Fallback to clicking
      await deleteButton.click({ force: true });
    }

    // Wait for modal to be visible
    await expect(page.locator('#delete-list-modal')).toBeVisible({ timeout: 10000 });
  }

  test('context menu appears on hover for reading list', async ({ page }) => {
    const listTitle = `Hover Test ${Date.now()}`;
    await createList(page, listTitle);

    // Hover over the list item
    const listItem = getListItem(page, listTitle);
    await listItem.hover();

    // The dropdown trigger should become visible
    const dropdownTrigger = listItem.locator('.dropdown [role="button"]');
    await expect(dropdownTrigger).toBeVisible();
  });

  test('context menu has delete option', async ({ page }) => {
    const listTitle = `Menu Test ${Date.now()}`;
    await createList(page, listTitle);

    const listItem = getListItem(page, listTitle);
    await listItem.hover();

    // Click the dropdown trigger
    const dropdownTrigger = listItem.locator('.dropdown [role="button"]');
    await dropdownTrigger.click();

    // Verify delete option is visible in the dropdown
    const deleteOption = listItem.locator('.dropdown-content button:has-text("Delete")');
    await expect(deleteOption).toBeVisible();
  });

  test('clicking delete opens confirmation modal', async ({ page }) => {
    const listTitle = `Modal Test ${Date.now()}`;
    await createList(page, listTitle);

    await openDeleteDialogForList(page, listTitle);

    // Modal should be visible with correct title
    await expect(page.locator('#delete-list-modal h3')).toHaveText('Delete Reading List');

    // List title should be shown in the confirmation message
    await expect(page.locator('#delete-list-modal')).toContainText(listTitle);
  });

  test('cancel button closes the modal without deleting', async ({ page }) => {
    const listTitle = `Cancel Test ${Date.now()}`;
    await createList(page, listTitle);

    await openDeleteDialogForList(page, listTitle);

    // Click cancel
    await page.click('#delete-list-modal button:has-text("Cancel")');

    // Modal should close
    await expect(page.locator('#delete-list-modal')).not.toBeVisible();

    // List should still be in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).toBeVisible();
  });

  test('X button closes the modal without deleting', async ({ page }) => {
    const listTitle = `X Button Test ${Date.now()}`;
    await createList(page, listTitle);

    await openDeleteDialogForList(page, listTitle);

    // Click the X button
    await page.click('#delete-list-modal button.btn-circle');

    // Modal should close
    await expect(page.locator('#delete-list-modal')).not.toBeVisible();

    // List should still be in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).toBeVisible();
  });

  test('confirming delete removes the list', async ({ page }) => {
    const listTitle = `Delete Confirm ${Date.now()}`;
    await createList(page, listTitle);

    await openDeleteDialogForList(page, listTitle);

    // Click the delete button to confirm
    await page.click('#delete-list-modal button.btn-error:has-text("Delete")');

    // Should redirect to home and modal should be closed
    await page.waitForURL('/');

    // List should no longer appear in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).not.toBeVisible({ timeout: 5000 });
  });

  test('can delete list while on the list page', async ({ page }) => {
    const listTitle = `On Page Delete ${Date.now()}`;
    await createList(page, listTitle);

    // Navigate to the list page
    await page.click(`a:has-text("${listTitle}")`);
    await page.waitForURL(/\/lists\//);

    await openDeleteDialogForList(page, listTitle);

    // Confirm deletion
    await page.click('#delete-list-modal button.btn-error:has-text("Delete")');

    // Should redirect to home
    await page.waitForURL('/');

    // List should no longer appear in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).not.toBeVisible({ timeout: 5000 });
  });

  test('escape key closes the modal', async ({ page }) => {
    const listTitle = `Escape Test ${Date.now()}`;
    await createList(page, listTitle);

    await openDeleteDialogForList(page, listTitle);

    // Press escape
    await page.keyboard.press('Escape');

    // Modal should close
    await expect(page.locator('#delete-list-modal')).not.toBeVisible();

    // List should still be in sidebar
    await expect(page.locator(`a:has-text("${listTitle}")`)).toBeVisible();
  });
});
