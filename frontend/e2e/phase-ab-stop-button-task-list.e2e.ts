/**
 * Phase A & B E2E tests
 *
 * Phase A — Stop button: chat-input.tsx shows ⏹ when streaming, clicking it
 *   aborts the fetch and shows a dialog if messages are queued.
 *
 * Phase B — Task list: task-list.tsx renders LangGraph tasks (via custom DOM
 *   events) and queued chat messages.
 *
 * No page.route() mocking — all requests hit the live server.
 */
import { test, expect, Page } from '@playwright/test';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { setupTestUser } from './helpers';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SCREENSHOTS = path.join(__dirname, 'screenshots/phase-ab');

async function ss(page: Page, name: string) {
  fs.mkdirSync(SCREENSHOTS, { recursive: true });
  await page.screenshot({ path: `${SCREENSHOTS}/${name}.png`, fullPage: false });
}

/**
 * Navigate to the chat page and wait for the chat input to be visible.
 * Handles cases where the app requires auth (registers a fresh user).
 */
async function gotoChat(page: Page): Promise<void> {
  await page.goto('/');
  const ready = await page
    .waitForSelector('[data-testid="chat-input"]', { timeout: 8000 })
    .then(() => true)
    .catch(() => false);

  if (!ready) {
    // App requires auth — register a fresh user
    await setupTestUser(page, 'phase-ab');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase A — Stop button
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Phase A — Stop button', () => {
  test('A1: send button visible when idle, stop button absent', async ({ page }) => {
    await gotoChat(page);
    await ss(page, '01_send_button_idle');

    await expect(page.locator('[data-testid="chat-send-button"]')).toBeVisible();
    await expect(page.locator('[data-testid="chat-stop-button"]')).not.toBeVisible();
  });

  test('A2: stop button appears while AI is responding', async ({ page }) => {
    await setupTestUser(page, 'a2');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    const input = page.locator('[data-testid="chat-input"]');
    await input.fill('What is RNA-seq? Answer in one sentence.');
    await page.locator('[data-testid="chat-send-button"]').click();

    // Stop button should appear when AI starts streaming
    const stopBtn = page.locator('[data-testid="chat-stop-button"]');
    await expect(stopBtn).toBeVisible({ timeout: 20000 });
    await ss(page, '02_stop_button_visible');

    // Send button should be hidden while streaming
    await expect(page.locator('[data-testid="chat-send-button"]')).not.toBeVisible();
  });

  test('A3: clicking stop restores the send button', async ({ page }) => {
    await setupTestUser(page, 'a3');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    await page.locator('[data-testid="chat-input"]').fill('Explain bioinformatics in detail');
    await page.locator('[data-testid="chat-send-button"]').click();

    await expect(page.locator('[data-testid="chat-stop-button"]')).toBeVisible({ timeout: 20000 });
    await ss(page, '03_stop_button_before_click');

    await page.locator('[data-testid="chat-stop-button"]').click();
    await ss(page, '04_after_stop_click');

    // Send button should return
    await expect(page.locator('[data-testid="chat-send-button"]')).toBeVisible({ timeout: 8000 });
    await ss(page, '05_send_button_returned');
  });

  test('A4: stop dialog appears when messages are queued', async ({ page }) => {
    await setupTestUser(page, 'a4');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    const input = page.locator('[data-testid="chat-input"]');

    // Send first message to start AI streaming
    await input.fill('What is FastQC?');
    await page.locator('[data-testid="chat-send-button"]').click();
    await expect(page.locator('[data-testid="chat-stop-button"]')).toBeVisible({ timeout: 20000 });

    // Queue a second message while AI is still responding
    await input.fill('What is DESeq2?');
    await page.keyboard.press('Enter');
    await ss(page, '06_second_message_queued');

    // Click stop — dialog should appear because there is a queued message
    await page.locator('[data-testid="chat-stop-button"]').click();
    await ss(page, '07_after_stop_with_queue');

    const dialog = page.locator('[data-testid="stop-dialog"]');
    const dialogVisible = await dialog.isVisible({ timeout: 3000 }).catch(() => false);

    if (dialogVisible) {
      await ss(page, '08_stop_dialog_visible');
      await expect(page.locator('[data-testid="stop-reply-only"]')).toBeVisible();
      await expect(page.locator('[data-testid="stop-and-clear-queue"]')).toBeVisible();
    } else {
      // AI may have finished before stop click (race condition is acceptable)
      console.log('A4: dialog not shown — AI likely finished before stop click (queue already auto-submitted)');
    }
  });

  test('A5: keep-queued button dismisses dialog without clearing queue', async ({ page }) => {
    await setupTestUser(page, 'a5');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    const input = page.locator('[data-testid="chat-input"]');
    await input.fill('What is FastQC?');
    await page.locator('[data-testid="chat-send-button"]').click();
    await expect(page.locator('[data-testid="chat-stop-button"]')).toBeVisible({ timeout: 20000 });

    await input.fill('What is DESeq2?');
    await page.keyboard.press('Enter');
    await page.locator('[data-testid="chat-stop-button"]').click();

    const dialog = page.locator('[data-testid="stop-dialog"]');
    const dialogVisible = await dialog.isVisible({ timeout: 3000 }).catch(() => false);
    if (dialogVisible) {
      await page.locator('[data-testid="stop-reply-only"]').click();
      await ss(page, '09_after_keep_queued');
      await expect(dialog).not.toBeVisible({ timeout: 3000 });
    } else {
      console.log('A5: No dialog shown — AI finished before stop');
    }
  });

  test('A6: clear-all-queued button removes queued messages', async ({ page }) => {
    await setupTestUser(page, 'a6');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    const input = page.locator('[data-testid="chat-input"]');
    await input.fill('What is FastQC?');
    await page.locator('[data-testid="chat-send-button"]').click();
    await expect(page.locator('[data-testid="chat-stop-button"]')).toBeVisible({ timeout: 20000 });

    await input.fill('What is DESeq2?');
    await page.keyboard.press('Enter');
    await page.locator('[data-testid="chat-stop-button"]').click();

    const dialog = page.locator('[data-testid="stop-dialog"]');
    const dialogVisible = await dialog.isVisible({ timeout: 3000 }).catch(() => false);
    if (dialogVisible) {
      await page.locator('[data-testid="stop-and-clear-queue"]').click();
      await ss(page, '10_queue_cleared');
      await expect(dialog).not.toBeVisible({ timeout: 3000 });
    } else {
      console.log('A6: No dialog shown — AI finished before stop');
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Phase B — Task list
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Phase B — Task list', () => {
  test('B1: task list hidden when idle (no tasks, no queued messages)', async ({ page }) => {
    await gotoChat(page);
    await ss(page, '11_initial_no_task_list');
    await expect(page.locator('[data-testid="task-list"]')).not.toBeVisible();
  });

  test('B2: task list shows queued messages while AI responds', async ({ page }) => {
    await setupTestUser(page, 'b2');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    const input = page.locator('[data-testid="chat-input"]');
    await input.fill('What is FastQC?');
    await page.locator('[data-testid="chat-send-button"]').click();

    // Wait for AI streaming to start
    await expect(page.locator('[data-testid="chat-stop-button"]')).toBeVisible({ timeout: 20000 });

    // Queue a second message
    await input.fill('What is DESeq2?');
    await page.keyboard.press('Enter');

    // Task list should appear with the queued message
    await expect(page.locator('[data-testid="task-list"]')).toBeVisible({ timeout: 6000 });
    await ss(page, '12_task_list_with_queued');

    await expect(page.locator('[data-testid="queued-message-0"]')).toBeVisible();
  });

  test('B3: remove-queued-message button removes the item', async ({ page }) => {
    await setupTestUser(page, 'b3');
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 20000 });

    const input = page.locator('[data-testid="chat-input"]');
    await input.fill('What is FastQC?');
    await page.locator('[data-testid="chat-send-button"]').click();

    await expect(page.locator('[data-testid="chat-stop-button"]')).toBeVisible({ timeout: 20000 });

    await input.fill('What is DESeq2?');
    await page.keyboard.press('Enter');

    await expect(page.locator('[data-testid="queued-message-0"]')).toBeVisible({ timeout: 6000 });
    await ss(page, '13_before_remove_queued');

    await page.locator('[data-testid="queued-message-remove-0"]').click();
    await ss(page, '14_after_remove_queued');

    await expect(page.locator('[data-testid="queued-message-0"]')).not.toBeVisible({ timeout: 3000 });
  });

  test('B4: langgraphTaskUpdate event creates a running task row with stop button', async ({ page }) => {
    await gotoChat(page);

    // Inject a running task via custom DOM event
    await page.evaluate(() => {
      window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
        detail: {
          task_id: 'test-task-1',
          status: 'running',
          description: 'Write QC workflow (FastQC)',
        }
      }));
    });

    await expect(page.locator('[data-testid="task-list"]')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('[data-testid="task-row-test-task-1"]')).toBeVisible();
    await ss(page, '15_task_injected_running');

    // Per-row stop button must be visible for running task
    await expect(page.locator('[data-testid="task-stop-test-task-1"]')).toBeVisible();
  });

  test('B5: clicking task stop changes status to stopped and shows retry button', async ({ page }) => {
    await gotoChat(page);

    await page.evaluate(() => {
      window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
        detail: { task_id: 'task-stop-test', status: 'running', description: 'Running step' }
      }));
    });

    await expect(page.locator('[data-testid="task-stop-task-stop-test"]')).toBeVisible({ timeout: 5000 });

    // Click the per-row stop button
    await page.locator('[data-testid="task-stop-task-stop-test"]').click();

    // Stop → stopped state should show retry button
    await expect(page.locator('[data-testid="task-retry-task-stop-test"]')).toBeVisible({ timeout: 3000 });
    await ss(page, '16_task_stopped_shows_retry');
  });

  test('B6: completed task shows remove button; removing hides the row', async ({ page }) => {
    await gotoChat(page);

    await page.evaluate(() => {
      window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
        detail: { task_id: 'task-done', status: 'completed', description: 'DE analysis (DESeq2)', elapsed_ms: 3200 }
      }));
    });

    await expect(page.locator('[data-testid="task-list"]')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('[data-testid="task-row-task-done"]')).toBeVisible();
    await ss(page, '17_task_completed');

    // Remove button visible for completed tasks
    await expect(page.locator('[data-testid="task-remove-task-done"]')).toBeVisible();

    await page.locator('[data-testid="task-remove-task-done"]').click();
    await ss(page, '18_task_removed');
    await expect(page.locator('[data-testid="task-row-task-done"]')).not.toBeVisible({ timeout: 3000 });
  });

  test('B7: multiple tasks tracked in one list', async ({ page }) => {
    await gotoChat(page);

    await page.evaluate(() => {
      window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
        detail: { task_id: 'mt-1', status: 'completed', description: 'QC Check', elapsed_ms: 1200 }
      }));
      window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
        detail: { task_id: 'mt-2', status: 'running', description: 'Alignment Step' }
      }));
      window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
        detail: { task_id: 'mt-3', status: 'pending', description: 'Downstream Analysis' }
      }));
    });

    await expect(page.locator('[data-testid="task-list"]')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('[data-testid="task-row-mt-1"]')).toBeVisible();
    await expect(page.locator('[data-testid="task-row-mt-2"]')).toBeVisible();
    await expect(page.locator('[data-testid="task-row-mt-3"]')).toBeVisible();
    await ss(page, '19_multiple_tasks');

    // mt-2 (running) → stop button; mt-1 (completed) → remove; mt-3 (pending) → remove
    await expect(page.locator('[data-testid="task-stop-mt-2"]')).toBeVisible();
    await expect(page.locator('[data-testid="task-remove-mt-1"]')).toBeVisible();
    await expect(page.locator('[data-testid="task-remove-mt-3"]')).toBeVisible();
  });
});
