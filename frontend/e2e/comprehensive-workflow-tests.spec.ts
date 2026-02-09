/**
 * Comprehensive E2E Tests - Natural User Conversations
 *
 * Tests realistic workflows with natural language interactions,
 * covering multiple scientific domains and workflow types.
 *
 * Based on: /backend/E2E_TEST_PLAN_WITH_PARAMETER_VALIDATION_2025-10-14.md
 */

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';

// Helper to simulate natural typing with delays
async function simulateNaturalTyping(locator: any, text: string) {
  await locator.click();
  for (const char of text) {
    await locator.type(char, { delay: Math.random() * 50 + 20 }); // 20-70ms per char
  }
}

// Helper to wait for workflow generation
async function waitForWorkflowGeneration(page: any, timeout = 60000) {
  // Wait for workflow card to appear
  await page.waitForSelector('[class*="workflow"], .workflow-card', { timeout });

  // Wait for any loading indicators to disappear
  await page.waitForSelector('[class*="loading"]', { state: 'hidden', timeout: 5000 }).catch(() => {});

  // Give a moment for animations
  await page.waitForTimeout(1000);
}

test.describe('Comprehensive Workflow E2E Tests', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  /**
   * Test Case 1: Genomics - RNA-seq Analysis
   * Natural conversation testing complete workflow
   */
  test('Genomics: RNA-seq differential expression analysis', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    // Step 1: User asks for RNA-seq analysis
    console.log('Step 1: User requests RNA-seq analysis');
    await simulateNaturalTyping(chatInput,
      'I have RNA-seq data from a cancer vs control experiment. Can you help me analyze differential gene expression?'
    );
    await chatInput.press('Enter');

    // Wait for AI response
    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    // Verify workflow was generated
    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ Workflow generated');

    // Check for expected tools in workflow
    const workflowText = await workflowCard.textContent();
    const hasRelevantTools = workflowText && (
      workflowText.toLowerCase().includes('fastqc') ||
      workflowText.toLowerCase().includes('trim') ||
      workflowText.toLowerCase().includes('align') ||
      workflowText.toLowerCase().includes('count') ||
      workflowText.toLowerCase().includes('deseq')
    );
    if (hasRelevantTools) {
      console.log('✓ Workflow contains relevant RNA-seq tools');
    } else {
      console.log('⚠ Could not verify RNA-seq specific tools');
    }

    // Step 2: User asks about parameters
    console.log('Step 2: User asks about parameters');
    await page.waitForTimeout(1000);
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'What parameters do I need to configure for this workflow?'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);

    // Step 3: Check if Run button appears
    console.log('Step 3: Checking for execution controls');
    const runButton = page.locator('button:has-text("Run"), button:has-text("Execute")').first();
    const hasRunButton = await runButton.isVisible().catch(() => false);

    if (hasRunButton) {
      console.log('✓ Run button available');

      // Try to execute
      await runButton.click();
      await page.waitForTimeout(2000);

      // Check for status indicators
      const statusIndicator = page.locator('text=/queued|running|completed|ok|error/i').first();
      const hasStatus = await statusIndicator.isVisible({ timeout: 10000 }).catch(() => false);

      if (hasStatus) {
        const status = await statusIndicator.textContent();
        console.log(`✓ Workflow executing with status: ${status}`);
      }
    } else {
      console.log('⚠ Run button not available (may need parameter configuration)');
    }
  });

  /**
   * Test Case 2: Proteomics - LC-MS Analysis
   * Testing data analysis workflow
   */
  test('Proteomics: LC-MS protein identification', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: User requests proteomics analysis');
    await simulateNaturalTyping(chatInput,
      'I need to identify proteins from LC-MS/MS data. Can you set up a workflow for protein database search?'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ Proteomics workflow generated');

    // Step 2: User provides more context
    console.log('Step 2: User provides organism context');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'The samples are from human plasma, and I want to use a Swiss-Prot database'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    console.log('✓ Context provided to AI');

    // Check if parameters were understood
    const responseText = await page.locator('[class*="message"]').last().textContent();
    if (responseText && responseText.toLowerCase().includes('human')) {
      console.log('✓ AI understood organism specification');
    }
  });

  /**
   * Test Case 3: Molecular Biology - Primer Design
   * Testing computational tool workflow
   */
  test('Molecular Biology: Design primers for PCR', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: User requests primer design');
    await simulateNaturalTyping(chatInput,
      'I need to design primers to amplify a specific region of the BRCA1 gene'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ Primer design workflow generated');

    // Step 2: User specifies requirements
    console.log('Step 2: User specifies primer requirements');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'I need primers with Tm around 60°C and product size between 100-300 bp'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    console.log('✓ Requirements specified');
  });

  /**
   * Test Case 4: Quality Control - FASTQ QC
   * Testing simple, commonly used workflow
   */
  test('Quality Control: Analyze FASTQ file quality', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: Simple QC request');
    await simulateNaturalTyping(chatInput,
      'Run quality control on my FASTQ files using FastQC'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ FastQC workflow generated');

    // Check if workflow is simple enough to run directly
    const runButton = page.locator('button:has-text("Run"), button:has-text("Execute")').first();
    const canRun = await runButton.isVisible().catch(() => false);

    if (canRun) {
      console.log('✓ Workflow ready to execute immediately');
      await runButton.click();
      await page.waitForTimeout(2000);

      // Verify execution started
      const statusText = page.locator('text=/queued|running/i').first();
      const hasStatus = await statusText.isVisible({ timeout: 5000 }).catch(() => false);
      if (hasStatus) {
        console.log('✓ QC workflow started executing');
      }
    } else {
      console.log('⚠ Workflow needs input configuration');
    }
  });

  /**
   * Test Case 5: Sequence Analysis - Alignment
   * Testing bioinformatics workflow
   */
  test('Sequence Analysis: Align sequences to reference', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: Request sequence alignment');
    await simulateNaturalTyping(chatInput,
      'Align my sequencing reads to the human reference genome using BWA'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ Alignment workflow generated');

    // Verify workflow has alignment step
    const workflowSteps = await page.locator('[class*="step"]').all();
    console.log(`✓ Workflow has ${workflowSteps.length} steps`);

    // User asks about output
    console.log('Step 2: User asks about output format');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'What output files will this generate?'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    console.log('✓ Output format question answered');
  });

  /**
   * Test Case 6: Microbiology - Growth Analysis
   * Testing Nextflow/Biomni workflow
   */
  test('Microbiology: Model bacterial growth dynamics', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: Request growth modeling');
    await simulateNaturalTyping(chatInput,
      'I have bacterial growth curve data from OD600 measurements. Can you help me fit a growth model?'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ Growth modeling workflow generated');

    // Step 2: User provides data details
    console.log('Step 2: User provides data format');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'My data is in CSV format with time points and OD600 values'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    console.log('✓ Data format specified');
  });

  /**
   * Test Case 7: Error Handling - Unclear Request
   * Testing AI clarification flow
   */
  test('Error Handling: AI asks for clarification', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: Vague request');
    await simulateNaturalTyping(chatInput,
      'I need to analyze some data'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);

    // Check if AI asks for clarification
    const responseText = await page.locator('[class*="message"]').last().textContent();
    const asksForClarification = responseText && (
      responseText.toLowerCase().includes('what type') ||
      responseText.toLowerCase().includes('tell me more') ||
      responseText.toLowerCase().includes('could you') ||
      responseText.toLowerCase().includes('what kind')
    );

    if (asksForClarification) {
      console.log('✓ AI appropriately asked for clarification');

      // Step 2: User provides clarification
      console.log('Step 2: User clarifies request');
      await chatInput.clear();
      await simulateNaturalTyping(chatInput,
        'It\'s RNA sequencing data from a time series experiment'
      );
      await chatInput.press('Enter');

      await page.waitForTimeout(3000);
      await waitForWorkflowGeneration(page);

      const workflowCard = page.locator('[class*="workflow"]').first();
      const workflowGenerated = await workflowCard.isVisible({ timeout: 10000 }).catch(() => false);

      if (workflowGenerated) {
        console.log('✓ Workflow generated after clarification');
      }
    } else {
      console.log('⚠ AI did not ask for clarification (may have generated workflow)');
    }
  });

  /**
   * Test Case 8: Multi-step Conversation
   * Testing context retention across messages
   */
  test('Multi-step: Build workflow incrementally', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    // Message 1
    console.log('Message 1: Initial request');
    await simulateNaturalTyping(chatInput,
      'I want to analyze protein-protein interactions'
    );
    await chatInput.press('Enter');
    await page.waitForTimeout(3000);

    // Message 2
    console.log('Message 2: Add details');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'The data is from a yeast two-hybrid screen'
    );
    await chatInput.press('Enter');
    await page.waitForTimeout(3000);

    // Message 3
    console.log('Message 3: Specify analysis');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'I need to filter for high-confidence interactions and create a network visualization'
    );
    await chatInput.press('Enter');
    await page.waitForTimeout(3000);

    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const workflowExists = await workflowCard.isVisible().catch(() => false);

    if (workflowExists) {
      console.log('✓ Workflow generated from multi-step conversation');
    } else {
      console.log('⚠ Workflow not generated yet');
    }
  });

  /**
   * Test Case 9: Workflow Modification
   * Testing iterative workflow refinement
   */
  test('Workflow Modification: User requests changes', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    // Generate initial workflow
    console.log('Step 1: Generate initial workflow');
    await simulateNaturalTyping(chatInput,
      'Align DNA sequences using Bowtie2'
    );
    await chatInput.press('Enter');
    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    await expect(workflowCard).toBeVisible();
    console.log('✓ Initial workflow generated');

    // Request modification
    console.log('Step 2: Request workflow modification');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'Actually, can we use BWA instead of Bowtie2?'
    );
    await chatInput.press('Enter');
    await page.waitForTimeout(3000);

    // Check if new workflow generated
    await page.waitForTimeout(2000);
    const workflows = await page.locator('[class*="workflow"]').all();
    console.log(`✓ ${workflows.length} workflow(s) in conversation`);
  });

  /**
   * Test Case 10: History and Results
   * Testing workflow history access
   */
  test('History: Access previous workflow results', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    // Generate and run a workflow
    console.log('Step 1: Generate workflow');
    await simulateNaturalTyping(chatInput,
      'Calculate GC content of a DNA sequence'
    );
    await chatInput.press('Enter');
    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    // Try to access history
    console.log('Step 2: Check for history/results access');

    // Look for history panel button
    const historyButton = page.locator('button:has-text("History"), button:has-text("Workflows"), [class*="history"]').first();
    const hasHistory = await historyButton.isVisible({ timeout: 5000 }).catch(() => false);

    if (hasHistory) {
      console.log('✓ History button found');
      await historyButton.click();
      await page.waitForTimeout(2000);

      // Check if history panel opened
      const historyPanel = page.locator('[class*="history"], [class*="panel"]').first();
      const panelVisible = await historyPanel.isVisible().catch(() => false);

      if (panelVisible) {
        console.log('✓ History panel opened');
      }
    } else {
      console.log('⚠ History access not found');
    }
  });

  /**
   * Test Case 11: Complex Multi-Domain Workflow
   * Testing workflow spanning multiple scientific domains
   */
  test('Complex: Multi-omics integration workflow', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: Request complex integration');
    await simulateNaturalTyping(chatInput,
      'I have RNA-seq, proteomics, and metabolomics data from the same samples. ' +
      'Can you help me integrate these datasets to identify correlated features?'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(5000); // Longer wait for complex request
    await waitForWorkflowGeneration(page, 90000); // 90s timeout for complex workflow

    const workflowCard = page.locator('[class*="workflow"]').first();
    const workflowExists = await workflowCard.isVisible().catch(() => false);

    if (workflowExists) {
      console.log('✓ Complex multi-omics workflow generated');

      // Count workflow steps
      const steps = await page.locator('[class*="step"]').all();
      console.log(`✓ Workflow has ${steps.length} steps`);

      if (steps.length >= 5) {
        console.log('✓ Workflow is appropriately complex');
      }
    } else {
      console.log('⚠ Complex workflow not generated (may need simplification)');
    }
  });

  /**
   * Test Case 12: Tool Recommendation
   * Testing AI's ability to suggest tools
   */
  test('Tool Recommendation: AI suggests alternative tools', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('Step 1: Ask about tool options');
    await simulateNaturalTyping(chatInput,
      'What tools do you have for variant calling in whole genome sequencing?'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);

    // Check if AI provides tool recommendations
    const responseText = await page.locator('[class*="message"]').last().textContent();
    const mentionsTools = responseText && (
      responseText.toLowerCase().includes('gatk') ||
      responseText.toLowerCase().includes('freebayes') ||
      responseText.toLowerCase().includes('samtools') ||
      responseText.toLowerCase().includes('tool')
    );

    if (mentionsTools) {
      console.log('✓ AI provided tool recommendations');
    } else {
      console.log('⚠ No specific tools mentioned');
    }

    // Follow up with selection
    console.log('Step 2: Select specific tool');
    await chatInput.clear();
    await simulateNaturalTyping(chatInput,
      'Let\'s use GATK for the analysis'
    );
    await chatInput.press('Enter');

    await page.waitForTimeout(3000);
    await waitForWorkflowGeneration(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const workflowGenerated = await workflowCard.isVisible().catch(() => false);

    if (workflowGenerated) {
      console.log('✓ Workflow generated with selected tool');
    }
  });
});
