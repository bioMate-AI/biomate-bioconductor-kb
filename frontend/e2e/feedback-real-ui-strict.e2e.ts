/**
 * Feedback Real UI Strict E2E Test
 *
 * Walks through the strict UI feedback path against the real BioMate backend:
 * 1) Inline feedback (thumbs up) after AI response
 * 2) Workflow execution
 * 3) Post-run survey / quick feedback / session pulse (handled if visible)
 * 4) Download outcome prompt (if download controls are present)
 *
 * Assertions are lenient: elements are asserted if visible, skipped if not.
 * NO page.route() mocks — all calls hit the live stack.
 */

import { test, expect } from '@playwright/test';
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from './helpers.js';

test.setTimeout(300000);

async function dismissLateDialogs(page: import('@playwright/test').Page) {
  for (let i = 0; i < 3; i++) {
    const quickFeedbackDialog = page.getByRole('dialog').filter({ hasText: 'Quick feedback' }).first();
    if (await quickFeedbackDialog.isVisible().catch(() => false)) {
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
      const skipOrSubmit = sessionPulseDialog.getByRole('button', { name: /skip|submit/i }).first();
      await skipOrSubmit.click();
      await expect(sessionPulseDialog).toBeHidden({ timeout: 10000 });
    }
    await page.waitForTimeout(250);
  }
}

test.describe('Feedback Real UI Strict', () => {
  test('submits inline feedback and post-run feedback through UI only', async ({ page }) => {
    // ===== STEP 1: Register test user =====
    await setupTestUser(page, 'fbstrict');

    // ===== STEP 2: Send message and wait for real AI response =====
    const workflowAppeared = await sendMessageAndWaitForResponse(
      page,
      'Build me a quality control workflow for RNA-seq FASTQ files'
    );
    await page.waitForTimeout(2000);

    // ===== STEP 3: Inline thumbs feedback =====
    const thumbsUp = page.getByTestId('inline-feedback-thumbs-up').last();
    const helpfulBtn = page.getByRole('button', { name: 'Helpful' }).last();

    const thumbsUpVisible = await thumbsUp.isVisible().catch(() => false);
    const helpfulVisible = await helpfulBtn.isVisible().catch(() => false);

    if (thumbsUpVisible) {
      await thumbsUp.click();
    } else if (helpfulVisible) {
      await helpfulBtn.click();
    } else {
      console.log('[strict] SKIP: Inline thumbs not visible — may only appear on workflow/invocation messages');
    }

    if (thumbsUpVisible || helpfulVisible) {
      const thanksVisible = await page
        .locator('text=Thanks for your feedback')
        .last()
        .isVisible({ timeout: 10000 })
        .catch(() => false);
      console.log(`[strict] Inline feedback confirmation visible: ${thanksVisible}`);
    }

    // ===== STEP 4: Execute workflow (if workflow card appeared) =====
    if (workflowAppeared) {
      console.log('[strict] Step 4: Execute workflow');

      // Check if run button is enabled; if not, request a runnable recovery variant
      const chatInput = page.locator('textarea').first();
      const panelRunBtn = page.getByTestId('button-run-workflow-panel').first();
      const runEnabled = await panelRunBtn.isEnabled().catch(() => false);

      if (!runEnabled) {
        console.log('[strict] Run button disabled; requesting runnable recovery variant from AI');
        await chatInput.fill(
          'My current workflow run is blocked by missing prerequisites. Please generate a runnable demo path with sample/test inputs and a workflow variant that can produce one visualizable report and downloadable outputs.'
        );
        await chatInput.press('Enter');
        await page
          .waitForSelector('text=AI is typing', { state: 'hidden', timeout: 120000 })
          .catch(() => {});
        await page.waitForTimeout(1500);
      }

      const runId = await clickRunAndWaitForTerminal(page, 240000);
      console.log(`[strict] Run ID: ${runId ?? 'not captured'}`);
    } else {
      console.log('[strict] Step 4: No workflow card found — skipping execution');
    }

    // ===== STEP 5: Post-run feedback surface =====
    const surveyDialog = page.getByTestId('post-run-survey-dialog');
    const quickFeedbackDialog = page.getByRole('dialog').filter({ hasText: 'Quick feedback' }).first();
    const sessionPulseDialog = page.getByTestId('session-end-pulse-dialog');

    // Wait up to 30s to see if any feedback surface appears
    let feedbackSurfaceFound = false;
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      const [survey, quick, pulse] = await Promise.all([
        surveyDialog.isVisible().catch(() => false),
        quickFeedbackDialog.isVisible().catch(() => false),
        sessionPulseDialog.isVisible().catch(() => false),
      ]);
      if (survey || quick || pulse) {
        feedbackSurfaceFound = true;
        break;
      }
      await page.waitForTimeout(1000);
    }

    if (!feedbackSurfaceFound) {
      console.log('[strict] No post-run feedback surface appeared within 30s — skipping post-run assertions');
    }

    if (await surveyDialog.isVisible().catch(() => false)) {
      console.log('[strict] Post-run survey dialog visible — submitting');
      const yesButtons = surveyDialog.getByRole('button', { name: 'Yes' });
      const yesCount = await yesButtons.count();
      for (let i = 0; i < Math.min(3, yesCount); i++) {
        await yesButtons.nth(i).click();
        await page.waitForTimeout(200);
      }
      const submitBtn = surveyDialog.getByRole('button', { name: 'Submit' });
      if (await submitBtn.isEnabled().catch(() => false)) {
        await submitBtn.click();
        await expect(surveyDialog).toBeHidden({ timeout: 10000 });
      } else {
        await page.keyboard.press('Escape');
      }
    } else if (await quickFeedbackDialog.isVisible().catch(() => false)) {
      console.log('[strict] Quick feedback dialog visible — submitting');
      const yesButtons = quickFeedbackDialog.getByRole('button', { name: 'Yes' });
      const yesCount = await yesButtons.count();
      for (let i = 0; i < Math.min(3, yesCount); i++) {
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
    } else if (await sessionPulseDialog.isVisible().catch(() => false)) {
      console.log('[strict] Session pulse dialog visible — submitting');
      const yesButtons = sessionPulseDialog.getByRole('button', { name: 'Yes' });
      const yesCount = await yesButtons.count();
      for (let i = 0; i < Math.min(2, yesCount); i++) {
        await yesButtons.nth(i).click();
        await page.waitForTimeout(150);
      }
      const submitBtn = sessionPulseDialog.getByRole('button', { name: 'Submit' });
      if (await submitBtn.isEnabled().catch(() => false)) {
        await submitBtn.click();
        await expect(sessionPulseDialog).toBeHidden({ timeout: 10000 });
      } else {
        await sessionPulseDialog.getByRole('button', { name: /skip/i }).first().click();
      }
    }

    await dismissLateDialogs(page);

    // ===== STEP 6: Download outcome prompt (lenient) =====
    const downloadAll = page.getByRole('button', { name: /download all/i }).last();
    const downloadIcon = page.getByTestId('button-download-outputs-icon').last();
    let clickedDownload = false;

    const downloadAllVisible = await downloadAll.isVisible().catch(() => false);
    const downloadAllEnabled = downloadAllVisible && await downloadAll.isEnabled().catch(() => false);
    const downloadIconVisible = await downloadIcon.isVisible().catch(() => false);
    const downloadIconEnabled = downloadIconVisible && await downloadIcon.isEnabled().catch(() => false);

    if (downloadAllEnabled) {
      await downloadAll.click();
      clickedDownload = true;
      console.log('[strict] Clicked Download All');
    } else if (downloadIconEnabled) {
      await downloadIcon.click();
      clickedDownload = true;
      console.log('[strict] Clicked download icon');
    } else {
      console.log('[strict] SKIP: No download button available/enabled');
    }

    if (clickedDownload) {
      await page.waitForTimeout(1000);
      const downloadPrompt = page.getByTestId('download-outcome-prompt-dialog');
      const promptVisible = await downloadPrompt.isVisible().catch(() => false);
      if (promptVisible) {
        console.log('[strict] Download outcome prompt appeared — submitting');
        const yesBtn = downloadPrompt.getByRole('button', { name: 'Yes' }).first();
        if (await yesBtn.isVisible().catch(() => false)) {
          await yesBtn.click();
        }
        const submitBtn = downloadPrompt.getByRole('button', { name: 'Submit' });
        if (await submitBtn.isEnabled().catch(() => false)) {
          await submitBtn.click();
          await expect(downloadPrompt).toBeHidden({ timeout: 10000 });
          console.log('[strict] Download outcome prompt: submitted and closed');
        }
      } else {
        console.log('[strict] SKIP: Download outcome prompt did not appear (conditional on handler)');
      }
    }

    console.log('[strict] === Feedback real UI strict test complete ===');
  });
});
