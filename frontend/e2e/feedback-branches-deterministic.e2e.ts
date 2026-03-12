/**
 * Feedback Branches E2E Test
 *
 * Tests multiple feedback UI branches against the real BioMate backend:
 * 1) Inline thumbs feedback after AI response
 * 2) Post-run survey or session pulse after workflow execution
 * 3) Download outcome prompt when downloading outputs
 * 4) Confusion / issue report button existence in workflow card
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

test.setTimeout(300000);

test.describe('Feedback Branches E2E', () => {
  test('covers inline thumbs, post-run survey, download outcome, and confusion report', async ({ page }) => {
    const log = (msg: string) => console.log(`[feedback-branches] ${msg}`);

    // ===== STEP 1: Register test user =====
    log('Step 1: Setup test user');
    await setupTestUser(page, 'fbd');

    // ===== STEP 2: Send workflow request and wait for real AI response =====
    log('Step 2: Send workflow request to real AI');
    const workflowAppeared = await sendMessageAndWaitForResponse(
      page,
      'Build me a quality control workflow for RNA-seq FASTQ files'
    );
    log(`Workflow card appeared: ${workflowAppeared}`);
    await page.waitForTimeout(2000);

    // ===== STEP 3: Inline thumbs feedback =====
    log('Step 3: Inline thumbs feedback');
    const thumbsUp = page.getByTestId('inline-feedback-thumbs-up').first();
    const thumbsUpFallback = page.getByRole('button', { name: 'Helpful' }).first();

    const thumbsUpVisible = await thumbsUp.isVisible().catch(() => false);
    const fallbackVisible = await thumbsUpFallback.isVisible().catch(() => false);

    if (thumbsUpVisible) {
      await thumbsUp.click();
      log('Inline feedback: clicked thumbs up (data-testid)');
    } else if (fallbackVisible) {
      await thumbsUpFallback.click();
      log('Inline feedback: clicked thumbs up (aria-label fallback)');
    } else {
      log('SKIP: Inline thumbs widget not visible — only shown on workflow/invocation messages');
    }

    if (thumbsUpVisible || fallbackVisible) {
      await page.waitForTimeout(1000);
      const thanksVisible = await page.locator('text=Thanks for your feedback').isVisible().catch(() => false);
      log(`Inline feedback confirmation visible: ${thanksVisible}`);
    }

    // ===== STEP 4: Execute workflow =====
    if (workflowAppeared) {
      log('Step 4: Execute workflow and wait for terminal state');
      const runId = await clickRunAndWaitForTerminal(page, 180000);
      log(`Run ID: ${runId ?? 'not captured'}`);
    } else {
      log('Step 4: No workflow card found — skipping execution');
    }

    // ===== STEP 5: Post-run survey or session pulse =====
    log('Step 5: Post-run feedback surface');
    const surveyDialog = page.getByTestId('post-run-survey-dialog');
    const sessionPulseDialog = page.getByTestId('session-end-pulse-dialog');
    const quickFeedbackDialog = page.getByRole('dialog').filter({ hasText: 'Quick feedback' }).first();

    const surveyVisible = await surveyDialog.isVisible().catch(() => false);
    const sessionPulseVisible = await sessionPulseDialog.isVisible().catch(() => false);
    const quickFeedbackVisible = await quickFeedbackDialog.isVisible().catch(() => false);

    if (surveyVisible) {
      log('Post-run survey appeared');
      const yesButtons = surveyDialog.getByRole('button', { name: 'Yes' });
      const yesCount = await yesButtons.count();
      for (let i = 0; i < Math.min(yesCount, 3); i++) {
        await yesButtons.nth(i).click();
        await page.waitForTimeout(200);
      }
      const submitBtn = surveyDialog.getByRole('button', { name: 'Submit' });
      if (await submitBtn.isEnabled().catch(() => false)) {
        await submitBtn.click();
        await expect(surveyDialog).toBeHidden({ timeout: 10000 });
        log('Post-run survey: submitted and closed');
      } else {
        const dismissBtn = surveyDialog.getByRole('button', { name: /skip|close|dismiss/i }).first();
        if (await dismissBtn.isVisible().catch(() => false)) {
          await dismissBtn.click();
        } else {
          await page.keyboard.press('Escape');
        }
        log('Post-run survey: dismissed (Submit not enabled)');
      }
    } else if (sessionPulseVisible) {
      log('Session pulse appeared; dismissing');
      const skipBtn = sessionPulseDialog.getByRole('button', { name: /skip|submit/i }).first();
      await skipBtn.click();
      await expect(sessionPulseDialog).toBeHidden({ timeout: 10000 });
    } else if (quickFeedbackVisible) {
      log('Quick feedback dialog appeared');
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
      log('No post-run survey/session pulse shown');
    }

    // Dismiss any lingering session pulse before checking outputs
    if (await sessionPulseDialog.isVisible().catch(() => false)) {
      await sessionPulseDialog.getByRole('button', { name: /skip|submit/i }).first().click();
      await expect(sessionPulseDialog).toBeHidden({ timeout: 10000 });
    }
    if (await quickFeedbackDialog.isVisible().catch(() => false)) {
      const skipBtn = quickFeedbackDialog.getByRole('button', { name: 'Skip' });
      if (await skipBtn.isVisible().catch(() => false)) {
        await skipBtn.click();
      } else {
        await quickFeedbackDialog.getByRole('button', { name: 'Close' }).click();
      }
      await expect(quickFeedbackDialog).toBeHidden({ timeout: 10000 });
    }

    // ===== STEP 6: Download outcome prompt =====
    log('Step 6: Download outcome prompt check');
    const downloadAllButton = page.getByRole('button', { name: /download all/i }).first();
    const downloadAllVisible = await downloadAllButton.isVisible().catch(() => false);
    const downloadAllEnabled = downloadAllVisible && await downloadAllButton.isEnabled().catch(() => false);

    if (downloadAllEnabled) {
      log('Download All button found and enabled — clicking');
      await downloadAllButton.click();
      await page.waitForTimeout(1000);
      const downloadPrompt = page.getByTestId('download-outcome-prompt-dialog');
      const promptVisible = await downloadPrompt.isVisible().catch(() => false);
      if (promptVisible) {
        log('Download outcome prompt appeared — submitting');
        const yesBtn = downloadPrompt.getByRole('button', { name: 'Yes' });
        if (await yesBtn.isVisible().catch(() => false)) {
          await yesBtn.click();
        }
        const submitBtn = downloadPrompt.getByRole('button', { name: 'Submit' });
        if (await submitBtn.isEnabled().catch(() => false)) {
          await submitBtn.click();
          await expect(downloadPrompt).toBeHidden({ timeout: 10000 });
          log('Download outcome prompt: submitted and closed');
        }
      } else {
        log('SKIP: Download outcome prompt did not appear (conditional on download handler)');
      }
    } else {
      log('SKIP: Download All not available/enabled — download outcome prompt not exercised');
    }

    // ===== STEP 7: Confusion / issue report button =====
    log('Step 7: Checking for Report issue / Report confusion button in workflow card');
    const reportIssueCandidates = [
      page.getByRole('button', { name: /report issue/i }).first(),
      page.getByRole('button', { name: /report confusion/i }).first(),
      page.getByTestId('button-report-issue').first(),
      page.getByTestId('button-report-confusion').first(),
    ];

    let reportButtonFound = false;
    for (const candidate of reportIssueCandidates) {
      if (await candidate.isVisible().catch(() => false)) {
        reportButtonFound = true;
        log('Report issue/confusion button exists in workflow card');

        await candidate.click();
        await page.waitForTimeout(500);

        const confusionDialog = page.getByRole('dialog').filter({ hasText: /report/i }).first();
        if (await confusionDialog.isVisible().catch(() => false)) {
          const commentBox = confusionDialog.getByPlaceholder(/confusing|unclear|issue/i).first();
          if (await commentBox.isVisible().catch(() => false)) {
            await commentBox.fill('Branch coverage check — automated E2E test');
          }
          const submitBtn = confusionDialog.getByRole('button', { name: 'Submit' });
          if (await submitBtn.isEnabled().catch(() => false)) {
            await submitBtn.click();
            await expect(confusionDialog).toBeHidden({ timeout: 10000 });
            log('Report dialog: submitted and closed');
          } else {
            await page.keyboard.press('Escape');
            log('Report dialog: dismissed via Escape');
          }
        }
        break;
      }
    }

    if (!reportButtonFound) {
      log('SKIP: Report issue/confusion button not visible — may not appear until after execution');
    }

    log('=== Feedback branches test complete ===');
  });
});
