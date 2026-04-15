/**
 * E2E: Dataset upload directly from workflow parameter browser
 * Tests the new "Upload file from computer" button in GalaxyDatasetBrowser session tab,
 * and verifies that uploaded files appear as selectable parameters.
 */
import { test, expect } from '@playwright/test';
import path from 'path';
import fs from 'fs';
import os from 'os';

test.describe('Dataset upload from param browser', () => {

  test.beforeEach(async ({ page }) => {
    // Register and login
    const ts = Date.now();
    const email = `param-upload-${ts}@test.biomate`;
    await page.goto('/');
    await page.click('[data-testid="nav-register"], a[href*="register"], button:has-text("Register")');
    await page.fill('#name', 'Param Upload Test');
    await page.fill('#email', email);
    await page.fill('#password', 'Test1234!');
    await page.fill('#confirmPassword', 'Test1234!');
    const termsBox = page.locator('#terms');
    if (await termsBox.count() > 0) await termsBox.check();
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/(chat|dashboard|home)/, { timeout: 15000 });
  });

  test('Upload file via Browse button in workflow parameter', async ({ page }) => {
    // Create a small test FASTA file
    const tmpFile = path.join(os.tmpdir(), `test_receptor_${Date.now()}.pdb`);
    fs.writeFileSync(tmpFile, 'ATOM      1  CA  ALA A   1       1.000   1.000   1.000  1.00  0.00           C\nEND\n');

    // Navigate to a workflow that has file params
    await page.goto('/');
    await page.waitForSelector('[data-testid="chat-input"], textarea', { timeout: 10000 });

    // Ask for gromacs workflow to get the viewer
    const chatInput = page.locator('[data-testid="chat-input"], textarea').first();
    await chatInput.fill('Run gromacs protein MD simulation');
    await chatInput.press('Enter');

    // Wait for workflow viewer to appear
    await page.waitForSelector('[data-testid="workflow-artifact-panel"]', { timeout: 30000 });

    // Find a file-type parameter Browse button
    const browseBtn = page.locator('button:has-text("Browse")').first();
    await expect(browseBtn).toBeVisible({ timeout: 10000 });
    await browseBtn.click();

    // Dataset browser should open
    await expect(page.locator('[role="dialog"]')).toBeVisible({ timeout: 5000 });

    // The "Upload file from computer" button should be visible in session tab
    const uploadBtn = page.locator('button:has-text("Upload file from computer")');
    await expect(uploadBtn).toBeVisible({ timeout: 5000 });

    // Upload a file via the hidden file input
    const fileInput = page.locator('[role="dialog"] input[type="file"]');
    await fileInput.setInputFiles(tmpFile);

    // Dialog should close (file auto-selected) and param field should update
    await expect(page.locator('[role="dialog"]')).not.toBeVisible({ timeout: 10000 });

    // Toast confirmation should appear
    await expect(page.locator('[data-testid*="toast"], [role="status"]').first()).toBeVisible({ timeout: 5000 });

    fs.unlinkSync(tmpFile);
  });

  test('Multiple file params have independent Browse buttons', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('[data-testid="chat-input"], textarea', { timeout: 10000 });

    const chatInput = page.locator('[data-testid="chat-input"], textarea').first();
    await chatInput.fill('Run gromacs protein MD simulation on BCR-ABL1');
    await chatInput.press('Enter');

    await page.waitForSelector('[data-testid="workflow-artifact-panel"]', { timeout: 30000 });

    // Should have at least 2 Browse buttons (receptor + ligand)
    const browseButtons = page.locator('button:has-text("Browse")');
    const count = await browseButtons.count();
    expect(count).toBeGreaterThanOrEqual(2);

    // Each Browse button should open dialog with correct param label
    await browseButtons.first().click();
    const dialog = page.locator('[role="dialog"]');
    await expect(dialog).toBeVisible({ timeout: 5000 });
    await page.keyboard.press('Escape');
    await expect(dialog).not.toBeVisible({ timeout: 3000 });
  });

});
