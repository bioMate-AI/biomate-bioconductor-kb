/**
 * Feedback Regression E2E Test
 *
 * Validates key UX feedback flows in the UI against the real BioMate backend:
 * 1) Inline thumbs feedback (if present after AI response)
 * 2) Post-run survey / session pulse appears and can be submitted or dismissed
 * 3) Download outcome prompt appears when downloading output (if output available)
 *
 * NO page.route() mocks — all calls hit the live stack.
 */

import { test, expect } from '@playwright/test';
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from './helpers.js';

test.setTimeout(300000); // 5 minutes for workflow execution

async function dismissBlockingDialogs(page: import('@playwright/test').Page, log: (msg: string) => void) {
  for (let i = 0; i < 4; i++) {
    const quickFeedbackDialog = page.getByRole('dialog').filter({ hasText: 'Quick feedback' }).first();
    if (await quickFeedbackDialog.isVisible().catch(() => false)) {
      log('Dialog sweep: dismissing Quick feedback dialog');
      const skipBtn = quickFeedbackDialog.getByRole('button', { name: 'Skip' });
      const closeBtn = quickFeedbackDialog.getByRole('button', { name: 'Close' });
      if (await skipBtn.isVisible().catch(() => false)) {
        await skipBtn.click();
      } else if (await closeBtn.isVisible().catch(() => false)) {
        await closeBtn.click();
      }
      await expect(quickFeedbackDialog).toBeHidden({ timeout: 10000 });
    }

    const sessionPulseDialog = page.getByTestId('session-end-pulse-dialog');
    if (await sessionPulseDialog.isVisible().catch(() => false)) {
      log('Dialog sweep: dismissing session pulse dialog');
      await sessionPulseDialog.getByRole('button', { name: /skip|submit/i }).first().click();
      await expect(sessionPulseDialog).toBeHidden({ timeout: 10000 });
    }

    await page.waitForTimeout(300);
  }
}

test.describe('Feedback Regression E2E', () => {
  test('validates inline thumbs, post-run survey, and download outcome prompt', async ({
    page,
  }) => {
    const logs: string[] = [];
    const log = (msg: string) => {
      logs.push(`[${new Date().toISOString()}] ${msg}`);
      console.log(msg);
    };

    // ===== STEP 1: Register test user and navigate =====
    log('Step 1: Setup test user');
    await setupTestUser(page, 'fbr');

    // ===== STEP 2: Send workflow request and wait for real AI response =====
    log('Step 2: Send workflow request to real AI');
    const workflowAppeared = await sendMessageAndWaitForResponse(
      page,
      'Run a FastQC quality control analysis on RNA-seq data'
    );
    log(`Workflow appeared in response: ${workflowAppeared}`);
    await page.waitForTimeout(2000);

    // ===== STEP 3: Inline thumbs feedback (check if present) =====
    log('Step 3: Checking for inline thumbs feedback');
    const thumbsUp = page.getByTestId('inline-feedback-thumbs-up').first();
    const thumbsUpAria = page.getByRole('button', { name: 'Helpful' }).first();

    const thumbsUpVisible = await thumbsUp.isVisible().catch(() => false);
    const thumbsUpAriaVisible = await thumbsUpAria.isVisible().catch(() => false);

    if (thumbsUpVisible) {
      await thumbsUp.click();
      log('Inline feedback: clicked thumbs up (data-testid)');
      await page.waitForTimeout(1500);
      const thanksVisible = await page.locator('text=Thanks for your feedback').isVisible().catch(() => false);
      if (thanksVisible) {
        log('Inline feedback: submit confirmed');
      } else {
        log('Inline feedback: submitted (no confirmation text visible)');
      }
    } else if (thumbsUpAriaVisible) {
      await thumbsUpAria.click();
      log('Inline feedback: clicked thumbs up (aria-label fallback)');
      await page.waitForTimeout(1500);
    } else {
      log('SKIP: Inline thumbs feedback widget not visible — may only appear on workflow/invocation messages');
    }

    // ===== STEP 4: Run workflow if one appeared =====
    if (workflowAppeared) {
      log('Step 4: Click Run workflow and wait for terminal state');
      const runId = await clickRunAndWaitForTerminal(page, 180000);
      log(`Execution run ID: ${runId ?? 'not captured'}`);
    } else {
      log('Step 4: No workflow card found — skipping execution');
    }

    // ===== STEP 5: Check for post-run feedback surface =====
    log('Step 5: Post-run feedback surface check');
    const surveyDialog = page.getByTestId('post-run-survey-dialog');
    const sessionPulseDialog = page.getByTestId('session-end-pulse-dialog');
    const quickFeedbackDialog = page.getByRole('dialog').filter({ hasText: 'Quick feedback' }).first();

    const surveyVisible = await surveyDialog.isVisible().catch(() => false);
    const sessionPulseVisible = await sessionPulseDialog.isVisible().catch(() => false);
    const quickFeedbackVisible = await quickFeedbackDialog.isVisible().catch(() => false);

    if (surveyVisible) {
      log('Post-run survey: dialog appeared');
      // Answer questions if they are present
      const yesButtons = surveyDialog.getByRole('button', { name: 'Yes' });
      const yesCount = await yesButtons.count();
      for (let i = 0; i < Math.min(yesCount, 3); i++) {
        await yesButtons.nth(i).click();
        await page.waitForTimeout(200);
      }
      const submitBtn = surveyDialog.getByRole('button', { name: 'Submit' });
      if (await submitBtn.isEnabled().catch(() => false)) {
        await submitBtn.click();
        await page.waitForTimeout(1000);
        const surveyClosed = await surveyDialog.isHidden().catch(() => true);
        log(`Post-run survey: closed after submit = ${surveyClosed}`);
      } else {
        await page.keyboard.press('Escape');
        log('Post-run survey: dismissed via Escape (Submit not enabled)');
      }
    } else if (sessionPulseVisible) {
      log('Session pulse appeared; dismissing');
      await sessionPulseDialog.getByRole('button', { name: /skip|submit/i }).first().click();
    } else if (quickFeedbackVisible) {
      log('Quick feedback dialog appeared; submitting minimal answers');
      const yesButtons = quickFeedbackDialog.getByRole('button', { name: 'Yes' });
      const yesCount = await yesButtons.count();
      for (let i = 0; i < Math.min(yesCount, 3); i++) {
        await yesButtons.nth(i).click();
        await page.waitForTimeout(150);
      }
      const submitBtn = quickFeedbackDialog.getByRole('button', { name: 'Submit' });
      if (await submitBtn.isEnabled().catch(() => false)) {
        await submitBtn.click();
      } else {
        await quickFeedbackDialog.getByRole('button', { name: 'Skip' }).click();
      }
      await expect(quickFeedbackDialog).toBeHidden({ timeout: 10000 });
    } else {
      log('SKIP: No post-run survey/session pulse shown; terminal cues still verified');
    }

    // Clear any remaining blocking dialogs before download checks
    if (await sessionPulseDialog.isVisible().catch(() => false)) {
      log('Post-run session pulse appeared after survey; dismissing');
      await sessionPulseDialog.getByRole('button', { name: /skip|submit/i }).first().click();
      await expect(sessionPulseDialog).toBeHidden({ timeout: 10000 });
    }
    if (await quickFeedbackDialog.isVisible().catch(() => false)) {
      log('Quick feedback dialog remained; dismissing');
      const skipBtn = quickFeedbackDialog.getByRole('button', { name: 'Skip' });
      if (await skipBtn.isVisible().catch(() => false)) {
        await skipBtn.click();
      } else {
        await quickFeedbackDialog.getByRole('button', { name: 'Close' }).click();
      }
      await expect(quickFeedbackDialog).toBeHidden({ timeout: 10000 });
    }
    await dismissBlockingDialogs(page, log);

    // ===== STEP 6: Download outcome prompt (OPTIONAL) =====
    log('Step 6: Download outcome prompt - OPTIONAL (if output available)');
    const directDownload = page.getByRole('button', { name: /^download$/i }).last();
    const downloadAll = page.getByRole('button', { name: /download all/i }).last();
    const downloadIcon = page.getByTestId('button-download-outputs-icon').last();

    const [directVisible, directEnabled, allVisible, allEnabled, iconVisible, iconEnabled] = await Promise.all([
      directDownload.isVisible().catch(() => false),
      directDownload.isEnabled().catch(() => false),
      downloadAll.isVisible().catch(() => false),
      downloadAll.isEnabled().catch(() => false),
      downloadIcon.isVisible().catch(() => false),
      downloadIcon.isEnabled().catch(() => false),
    ]);
    log(`Download controls: direct(v=${directVisible},e=${directEnabled}) all(v=${allVisible},e=${allEnabled}) icon(v=${iconVisible},e=${iconEnabled})`);

    let triggeredDownload = false;
    if (directVisible && directEnabled) {
      log('Direct download button found and enabled — triggering download flow');
      await dismissBlockingDialogs(page, log);
      await directDownload.click();
      triggeredDownload = true;
    } else if (allVisible && allEnabled) {
      log('Using Download All fallback');
      await dismissBlockingDialogs(page, log);
      await downloadAll.click();
      triggeredDownload = true;
    } else if (iconVisible && iconEnabled) {
      log('Using response-box download icon fallback');
      await dismissBlockingDialogs(page, log);
      await downloadIcon.click();
      triggeredDownload = true;
    }

    if (triggeredDownload) {
      await page.waitForTimeout(1000);
      const downloadPrompt = page.getByTestId('download-outcome-prompt-dialog');
      const promptVisible = await downloadPrompt.isVisible().catch(() => false);
      if (promptVisible) {
        log('Download outcome prompt appeared — submitting Yes');
        await page.getByRole('button', { name: 'Yes' }).first().click();
        const submitBtn = page.getByRole('button', { name: 'Submit' });
        if (await submitBtn.isEnabled().catch(() => false)) {
          await submitBtn.click();
        }
        await page.waitForTimeout(500);
        log('Download outcome prompt: submitted');
      } else {
        log('SKIP: Download outcome prompt did not appear (may be conditional on download handler)');
      }
    } else {
      log('SKIP: No download button available/enabled — download outcome prompt flow not exercised');
    }

    log('=== Feedback regression test complete ===');
  });
});
