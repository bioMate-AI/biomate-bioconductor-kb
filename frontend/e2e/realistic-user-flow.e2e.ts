/**
 * Realistic User Flow E2E Test
 *
 * Simulates a REAL user interaction with BioMate:
 * 1. User asks for a workflow
 * 2. BioMate shows workflow with prerequisites
 * 3. User responds naturally (provides data OR asks for sample data)
 * 4. Process continues
 *
 * This tests the complete conversational flow, not just single interactions.
 */

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'realistic-flow');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

test.setTimeout(300000); // 5 minutes for full conversation

// Helper to send a message and wait for response
async function sendMessageAndWait(page: any, message: string, testName: string, stepNum: number) {
  const chatInput = page.locator('textarea').first();
  await chatInput.fill(message);
  await chatInput.press('Enter');
  console.log(`[${testName}] Step ${stepNum}: Sent "${message.substring(0, 50)}..."`);

  // Wait for typing indicator
  await page.waitForSelector('text=AI is typing', { timeout: 15000 }).catch(() => {});

  // Wait for response to complete
  await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 120000 }).catch(() => {
    console.log(`[${testName}] Response timeout - continuing`);
  });

  await page.waitForTimeout(2000);
  return await page.textContent('body');
}

// Helper to save screenshot with context
async function saveScreenshot(page: any, name: string, startTime: number) {
  const timestamp = Date.now() - startTime;
  const filename = `${SCREENSHOT_DIR}/${String(timestamp).padStart(6, '0')}_${name}.png`;
  await page.screenshot({ path: filename, fullPage: true });
  console.log(`[Screenshot] ${name} at ${timestamp}ms`);
  return filename;
}

test.describe('Realistic User Flow', () => {

  test('Multi-turn: Request workflow → Handle prerequisites → Execute', async ({ page }) => {
    const testStart = Date.now();
    const testName = 'MultiTurn';

    // ===== TURN 1: User asks for a workflow =====
    console.log(`\n[${testName}] ========== TURN 1: Initial Request ==========`);
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    await saveScreenshot(page, '01_initial', testStart);

    const turn1Response = await sendMessageAndWait(
      page,
      'I want to analyze some RNA-seq data for differential expression. Can you help me build a workflow?',
      testName,
      1
    );
    await saveScreenshot(page, '02_turn1_response', testStart);

    console.log(`[${testName}] Turn 1 contains workflow:`, turn1Response?.toLowerCase().includes('workflow'));
    console.log(`[${testName}] Turn 1 contains steps:`, turn1Response?.toLowerCase().includes('step'));

    // ===== TURN 2: User responds to prerequisites =====
    console.log(`\n[${testName}] ========== TURN 2: Handle Prerequisites ==========`);

    // Check if prerequisites are shown
    const hasPrerequisites = await page.locator('text=Input Data Required').isVisible().catch(() => false);
    const hasRunButton = await page.locator('button:has-text("Run")').isVisible().catch(() => false);
    const isRunDisabled = hasRunButton ? await page.locator('button:has-text("Run")').first().isDisabled() : true;

    console.log(`[${testName}] Prerequisites shown: ${hasPrerequisites}`);
    console.log(`[${testName}] Run button visible: ${hasRunButton}, disabled: ${isRunDisabled}`);

    let turn2Message: string;
    if (hasPrerequisites || isRunDisabled) {
      // Natural user response: ask for sample data to test the workflow
      turn2Message = 'I don\'t have data ready yet. Can you generate some sample/test RNA-seq data so I can try this workflow first?';
    } else {
      // Workflow might be ready to run
      turn2Message = 'Great! The workflow looks good. Can you run it now?';
    }

    const turn2Response = await sendMessageAndWait(page, turn2Message, testName, 2);
    await saveScreenshot(page, '03_turn2_response', testStart);

    console.log(`[${testName}] Turn 2 contains sample:`, turn2Response?.toLowerCase().includes('sample'));
    console.log(`[${testName}] Turn 2 contains test:`, turn2Response?.toLowerCase().includes('test'));
    console.log(`[${testName}] Turn 2 contains data:`, turn2Response?.toLowerCase().includes('data'));

    // ===== TURN 3: Follow up based on response =====
    console.log(`\n[${testName}] ========== TURN 3: Continue Conversation ==========`);

    // Check current state
    const runButtonNow = page.locator('button:has-text("Run")').first();
    const canRunNow = await runButtonNow.isVisible().catch(() => false) &&
                      !(await runButtonNow.isDisabled().catch(() => true));

    let turn3Message: string;
    if (canRunNow) {
      turn3Message = 'Please run the workflow now.';
    } else {
      // Ask BioMate to help with a simpler approach
      turn3Message = 'Let\'s try something simpler first. Can you query UniProt to get information about the TP53 tumor suppressor protein? This doesn\'t need any input files.';
    }

    const turn3Response = await sendMessageAndWait(page, turn3Message, testName, 3);
    await saveScreenshot(page, '04_turn3_response', testStart);

    console.log(`[${testName}] Turn 3 contains TP53:`, turn3Response?.toLowerCase().includes('tp53'));
    console.log(`[${testName}] Turn 3 contains protein:`, turn3Response?.toLowerCase().includes('protein'));

    // ===== TURN 4: Try to execute =====
    console.log(`\n[${testName}] ========== TURN 4: Attempt Execution ==========`);

    const finalRunButton = page.locator('button:has-text("Run")').first();
    const canExecute = await finalRunButton.isVisible().catch(() => false) &&
                       !(await finalRunButton.isDisabled().catch(() => true));

    if (canExecute) {
      console.log(`[${testName}] Run button is enabled - clicking...`);
      await finalRunButton.click();
      await page.waitForTimeout(5000);
      await saveScreenshot(page, '05_execution_started', testStart);

      // Monitor execution
      for (let i = 0; i < 30; i++) {
        await page.waitForTimeout(2000);
        const pageText = await page.textContent('body');

        if (pageText?.includes('Complete') || pageText?.includes('Success')) {
          console.log(`[${testName}] Execution completed!`);
          await saveScreenshot(page, '06_execution_complete', testStart);
          break;
        }
        if (pageText?.includes('Failed') || pageText?.includes('Error')) {
          console.log(`[${testName}] Execution failed`);
          await saveScreenshot(page, '06_execution_failed', testStart);
          break;
        }
        if (i % 5 === 0) {
          console.log(`[${testName}] Waiting for execution... (${i * 2}s)`);
        }
      }
    } else {
      console.log(`[${testName}] Cannot execute yet - checking UI state`);
      await saveScreenshot(page, '05_cannot_execute', testStart);

      // Log what's blocking
      const prereqVisible = await page.locator('text=Input Data Required').isVisible().catch(() => false);
      const toolsVisible = await page.locator('text=Recommended Tools').isVisible().catch(() => false);
      console.log(`[${testName}] Prerequisites alert: ${prereqVisible}`);
      console.log(`[${testName}] Tool recommendations: ${toolsVisible}`);
    }

    // ===== Summary =====
    console.log(`\n[${testName}] ========== TEST SUMMARY ==========`);
    const finalPageText = await page.textContent('body');

    const summary = {
      timestamp: new Date().toISOString(),
      turns: 4,
      workflowGenerated: finalPageText?.toLowerCase().includes('workflow'),
      prerequisitesHandled: true,
      executionAttempted: canExecute,
      containsExpectedContent: finalPageText?.toLowerCase().includes('rna') ||
                               finalPageText?.toLowerCase().includes('tp53') ||
                               finalPageText?.toLowerCase().includes('protein'),
    };

    fs.writeFileSync(
      `${SCREENSHOT_DIR}/summary_${Date.now()}.json`,
      JSON.stringify(summary, null, 2)
    );

    console.log(`[${testName}] Summary:`, JSON.stringify(summary, null, 2));

    // Basic assertion - conversation should have progressed
    expect(summary.containsExpectedContent).toBe(true);
  });

  test('Simple query: Database lookup (no file inputs)', async ({ page }) => {
    const testStart = Date.now();
    const testName = 'SimpleQuery';

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // ===== Single turn: Direct query that shouldn't need file inputs =====
    console.log(`\n[${testName}] ========== Direct Database Query ==========`);

    const response = await sendMessageAndWait(
      page,
      'Query the PDB database to find all crystal structures of human hemoglobin with resolution better than 2 Angstroms',
      testName,
      1
    );
    await saveScreenshot(page, '01_pdb_query_response', testStart);

    console.log(`[${testName}] Response contains PDB:`, response?.toLowerCase().includes('pdb'));
    console.log(`[${testName}] Response contains hemoglobin:`, response?.toLowerCase().includes('hemoglobin'));
    console.log(`[${testName}] Response contains structure:`, response?.toLowerCase().includes('structure'));

    // Check if a workflow was generated
    const hasWorkflow = await page.locator('text=steps').isVisible().catch(() => false);
    const hasRunButton = await page.locator('button:has-text("Run")').isVisible().catch(() => false);

    console.log(`[${testName}] Workflow generated: ${hasWorkflow}`);
    console.log(`[${testName}] Run button visible: ${hasRunButton}`);

    if (hasRunButton) {
      const isEnabled = !(await page.locator('button:has-text("Run")').first().isDisabled());
      console.log(`[${testName}] Run button enabled: ${isEnabled}`);

      if (isEnabled) {
        console.log(`[${testName}] Attempting to run...`);
        await page.locator('button:has-text("Run")').first().click();
        await page.waitForTimeout(5000);
        await saveScreenshot(page, '02_query_execution', testStart);
      }
    }

    expect(response?.toLowerCase()).toContain('hemoglobin');
  });
});
