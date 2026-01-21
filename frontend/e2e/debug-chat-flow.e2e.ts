/**
 * Debug Chat Flow E2E Test
 *
 * Captures console logs, network activity, and errors to diagnose
 * why AI responses aren't displaying properly.
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const DEBUG_DIR = path.join(__dirname, 'debug-output');

if (!fs.existsSync(DEBUG_DIR)) fs.mkdirSync(DEBUG_DIR, { recursive: true });

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  viewport: { width: 1920, height: 1080 },
});

async function setupTestUser(page: Page): Promise<void> {
  const email = `e2e_debug_${Date.now()}@biomate.test`;
  const password = 'TestPass123!';

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState('networkidle');

  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
    await page.fill('#name', 'E2E Debug Tester');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.fill('#confirmPassword', password);
    await page.click('#terms');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {
    console.log('[Setup] Registration form not found');
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState('networkidle');
}

test.describe('Debug Chat Flow', () => {
  test('capture detailed chat flow diagnostics', async ({ page }) => {
    const consoleLogs: string[] = [];
    const networkRequests: any[] = [];
    const networkResponses: any[] = [];
    const errors: string[] = [];

    // Capture all console logs
    page.on('console', (msg) => {
      const text = `[${msg.type()}] ${msg.text()}`;
      consoleLogs.push(text);
      if (msg.type() === 'error') {
        errors.push(text);
      }
    });

    // Capture page errors
    page.on('pageerror', (error) => {
      errors.push(`[Page Error] ${error.message}`);
    });

    // Capture network requests
    page.on('request', (request) => {
      if (request.url().includes('/api/')) {
        networkRequests.push({
          url: request.url(),
          method: request.method(),
          postData: request.postData(),
          timestamp: new Date().toISOString(),
        });
      }
    });

    // Capture network responses
    page.on('response', async (response) => {
      if (response.url().includes('/api/')) {
        let body = '';
        try {
          body = await response.text();
        } catch {
          body = '[Could not read body]';
        }
        networkResponses.push({
          url: response.url(),
          status: response.status(),
          body: body.substring(0, 2000), // Truncate
          timestamp: new Date().toISOString(),
        });
      }
    });

    await setupTestUser(page);

    console.log('[Debug] User setup complete, sending message...');

    // Find and use chat input
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Clear any existing text
    await chatInput.clear();
    await page.waitForTimeout(500);

    // Type and send message
    const testMessage = 'What tools do you have for variant calling?';
    await chatInput.fill(testMessage);
    console.log('[Debug] Message filled');

    await chatInput.press('Enter');
    console.log('[Debug] Enter pressed');

    // Wait and observe
    await page.waitForTimeout(5000);

    // Check state
    const typingVisible = await page.locator('text=AI is typing').isVisible();
    console.log(`[Debug] After 5s - Typing indicator visible: ${typingVisible}`);

    // Wait more
    await page.waitForTimeout(10000);

    const typingVisibleAfter = await page.locator('text=AI is typing').isVisible();
    console.log(`[Debug] After 15s - Typing indicator visible: ${typingVisibleAfter}`);

    // Take screenshot
    await page.screenshot({
      path: `${DEBUG_DIR}/debug_chat_state.png`,
      fullPage: true,
    });

    // Get page content
    const pageContent = await page.textContent('body');

    // Save debug info
    const debugInfo = {
      timestamp: new Date().toISOString(),
      testMessage,
      consoleLogs,
      networkRequests,
      networkResponses,
      errors,
      typingIndicatorAfter5s: typingVisible,
      typingIndicatorAfter15s: typingVisibleAfter,
      pageContentSample: pageContent?.substring(0, 3000),
    };

    fs.writeFileSync(
      `${DEBUG_DIR}/debug_info.json`,
      JSON.stringify(debugInfo, null, 2)
    );

    console.log('\n=== DEBUG SUMMARY ===');
    console.log(`Console logs: ${consoleLogs.length}`);
    console.log(`Network requests: ${networkRequests.length}`);
    console.log(`Network responses: ${networkResponses.length}`);
    console.log(`Errors: ${errors.length}`);
    console.log(`Typing indicator still visible: ${typingVisibleAfter}`);

    if (errors.length > 0) {
      console.log('\n=== ERRORS ===');
      errors.forEach((e) => console.log(e));
    }

    // Print relevant console logs
    const chatLogs = consoleLogs.filter(
      (log) =>
        log.includes('ChatInterface') ||
        log.includes('API') ||
        log.includes('error') ||
        log.includes('Error')
    );
    if (chatLogs.length > 0) {
      console.log('\n=== RELEVANT CONSOLE LOGS ===');
      chatLogs.forEach((log) => console.log(log));
    }

    // Print API response
    const chatResponse = networkResponses.find((r) => r.url.includes('/api/chat'));
    if (chatResponse) {
      console.log('\n=== /api/chat RESPONSE ===');
      console.log(`Status: ${chatResponse.status}`);
      console.log(`Body preview: ${chatResponse.body.substring(0, 500)}`);
    } else {
      console.log('\n=== NO /api/chat RESPONSE FOUND ===');
    }

    // The test "passes" but outputs debug info
    expect(true).toBe(true);
  });
});
