import { setupTestUser } from "./helpers.js";
/**
 * Detailed Chat Flow Trace
 *
 * Traces every step with timestamps to identify bottlenecks.
 */

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const TRACE_DIR = path.join(__dirname, 'trace-output');

if (!fs.existsSync(TRACE_DIR)) fs.mkdirSync(TRACE_DIR, { recursive: true });

interface TraceStep {
  step: string;
  timestamp: string;
  elapsed_ms: number;
  data?: any;
}

test.describe('Trace Chat Flow', () => {
  test('trace every step with timing', async ({ page }) => {
    await setupTestUser(page, "trace");
    const startTime = Date.now();
    const steps: TraceStep[] = [];

    const addStep = (step: string, data?: any) => {
      const now = Date.now();
      steps.push({
        step,
        timestamp: new Date().toISOString(),
        elapsed_ms: now - startTime,
        data,
      });
      console.log(`[${now - startTime}ms] ${step}`, data ? JSON.stringify(data).substring(0, 200) : '');
    };

    // Capture all console logs
    page.on('console', (msg) => {
      if (msg.text().includes('ChatInterface') || msg.text().includes('API')) {
        addStep(`CONSOLE: ${msg.type()}`, msg.text().substring(0, 300));
      }
    });

    // Capture network with detailed timing
    page.on('request', (request) => {
      if (request.url().includes('/api/chat')) {
        addStep('REQUEST: /api/chat started', {
          method: request.method(),
          url: request.url(),
        });
      }
    });

    page.on('response', async (response) => {
      if (response.url().includes('/api/chat')) {
        let body = '';
        try {
          body = await response.text();
        } catch {}
        addStep('RESPONSE: /api/chat completed', {
          status: response.status(),
          bodyPreview: body.substring(0, 500),
        });
      }
    });

    page.on('requestfailed', (request) => {
      if (request.url().includes('/api/chat')) {
        addStep('REQUEST FAILED: /api/chat', {
          error: request.failure()?.errorText,
        });
      }
    });

    // Step 1: Navigate to app
    addStep('STEP 1: Navigate to app');
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    addStep('STEP 1: Navigation complete');

    // Step 2: Wait for chat interface
    addStep('STEP 2: Wait for chat interface');
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });
    addStep('STEP 2: Chat input visible');

    // Step 3: Check initial state
    addStep('STEP 3: Check initial state');
    const typingBefore = await page.locator('[data-testid="typing-indicator"]').isVisible();
    const messageCount = await page.locator('[data-role]').count();
    addStep('STEP 3: Initial state', { typingIndicator: typingBefore, messageCount });

    // Step 4: Fill message
    addStep('STEP 4: Fill message');
    const testMessage = 'Hello, what can you do?';
    await chatInput.fill(testMessage);
    addStep('STEP 4: Message filled');

    // Step 5: Send message (press Enter)
    addStep('STEP 5: Press Enter to send');
    await chatInput.press('Enter');
    addStep('STEP 5: Enter pressed');

    // Step 6: Check typing indicator immediately
    await page.waitForTimeout(100);
    const typingAfterSend = await page.locator('[data-testid="typing-indicator"]').isVisible();
    addStep('STEP 6: Typing indicator after send', { visible: typingAfterSend });

    // Step 7: Wait for response with polling
    addStep('STEP 7: Begin waiting for response');

    let responseReceived = false;
    let pollCount = 0;
    const maxPolls = 60; // 60 seconds max

    while (!responseReceived && pollCount < maxPolls) {
      await page.waitForTimeout(1000);
      pollCount++;

      const typing = await page.locator('[data-testid="typing-indicator"]').isVisible();
      const messages = await page.locator('[data-role="assistant"]').count();

      if (pollCount % 5 === 0) {
        addStep(`STEP 7: Poll ${pollCount}`, { typing, assistantMessages: messages });
      }

      if (!typing) {
        responseReceived = true;
        addStep('STEP 7: Typing indicator disappeared', { pollCount });
      }
    }

    // Step 8: Final state
    addStep('STEP 8: Check final state');
    const finalTyping = await page.locator('[data-testid="typing-indicator"]').isVisible();
    const finalMessages = await page.locator('[data-role="assistant"]').count();
    const pageContent = await page.textContent('body');

    addStep('STEP 8: Final state', {
      typingIndicator: finalTyping,
      assistantMessages: finalMessages,
      hasResponse: pageContent?.includes('Hello') || pageContent?.includes('help'),
    });

    // Save trace
    const traceFile = path.join(TRACE_DIR, `trace_${Date.now()}.json`);
    fs.writeFileSync(traceFile, JSON.stringify(steps, null, 2));
    addStep('TRACE: Saved to file', { file: traceFile });

    // Screenshot
    await page.screenshot({ path: path.join(TRACE_DIR, 'final_state.png'), fullPage: true });

    // Print summary
    console.log('\n=== TRACE SUMMARY ===');
    console.log(`Total steps: ${steps.length}`);
    console.log(`Total time: ${Date.now() - startTime}ms`);
    console.log(`Response received: ${responseReceived}`);
    console.log(`Final typing indicator: ${finalTyping}`);
    console.log(`Assistant messages: ${finalMessages}`);

    // Find key events
    const chatRequest = steps.find(s => s.step.includes('REQUEST: /api/chat'));
    const chatResponse = steps.find(s => s.step.includes('RESPONSE: /api/chat'));

    if (chatRequest) {
      console.log(`\nAPI Request at: ${chatRequest.elapsed_ms}ms`);
    } else {
      console.log('\n*** NO API REQUEST FOUND ***');
    }

    if (chatResponse) {
      console.log(`API Response at: ${chatResponse.elapsed_ms}ms`);
      console.log(`API Response time: ${chatResponse.elapsed_ms - (chatRequest?.elapsed_ms || 0)}ms`);
    } else {
      console.log('*** NO API RESPONSE FOUND ***');
    }

    expect(true).toBe(true); // Always pass for trace collection
  });
});
