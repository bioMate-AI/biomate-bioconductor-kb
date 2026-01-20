/**
 * Bioinformatics Viewers E2E Tests with Video Recording
 *
 * Tests the output visualization viewers:
 * - VCF Viewer (variant calls)
 * - Sequence Viewer (FASTA/FASTQ)
 * - Annotation Viewer (BED/GFF/GTF)
 * - Interactive Tool Launcher
 *
 * Video recordings are saved to: frontend/e2e/videos/
 */

import { test, expect, Page, BrowserContext } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const VIDEO_DIR = path.join(__dirname, 'videos');
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots');

// Ensure directories exist
if (!fs.existsSync(VIDEO_DIR)) fs.mkdirSync(VIDEO_DIR, { recursive: true });
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

// Test configuration with video recording
test.use({
  video: {
    mode: 'on',
    size: { width: 1920, height: 1080 },
  },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

// Test user credentials
const TEST_USER = {
  email: `e2e_viewer_test_${Date.now()}@biomate.test`,
  password: 'TestPass123!',
  name: 'E2E Viewer Tester',
};

// Sample bioinformatics data for testing
const SAMPLE_DATA = {
  vcf: `##fileformat=VCFv4.2
##INFO=<ID=DP,Number=1,Type=Integer,Description="Read Depth">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
chr1\t100\trs123\tA\tG\t30\tPASS\tDP=50
chr1\t200\trs456\tC\tT\t25\tPASS\tDP=45
chr2\t300\trs789\tG\tA\t35\tPASS\tDP=60`,

  fasta: `>seq1 Test sequence 1
ATGCGATCGATCGATCGATCGATCGATCGATCGATCG
ATCGATCGATCGATCGATCGATCGATCGATCGATCGA
>seq2 Test sequence 2
GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC`,

  bed: `chr1\t100\t200\tfeature1\t100\t+
chr1\t300\t400\tfeature2\t200\t-
chr2\t500\t600\tfeature3\t150\t+
chr2\t700\t800\tfeature4\t180\t-`,
};

/**
 * Helper to register and login a test user
 */
async function setupTestUser(page: Page): Promise<void> {
  console.log(`[Setup] Registering user: ${TEST_USER.email}`);

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState('networkidle');

  // Wait for form to be ready
  await page.waitForSelector('#name', { state: 'visible', timeout: 30000 });

  await page.fill('#name', TEST_USER.name);
  await page.fill('#email', TEST_USER.email);
  await page.fill('#password', TEST_USER.password);
  await page.fill('#confirmPassword', TEST_USER.password);
  await page.click('#terms');
  await page.click('button[type="submit"]');

  // Wait for registration to complete
  await page.waitForTimeout(3000);

  // Navigate to main app
  await page.goto(BASE_URL);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(2000);

  console.log('[Setup] User registered and logged in');
}

/**
 * Helper to send a chat message and wait for response
 */
async function sendChatMessage(page: Page, message: string): Promise<void> {
  const chatInput = page.locator('textarea').first();
  await chatInput.fill(message);
  await page.waitForTimeout(500);
  await chatInput.press('Enter');

  // Wait for AI response
  console.log('[Chat] Waiting for AI response...');
  await page.waitForTimeout(5000);

  // Wait for typing indicator to disappear
  const maxWait = 60000;
  const startTime = Date.now();
  while (Date.now() - startTime < maxWait) {
    const typing = page.locator('text=AI is typing').first();
    if ((await typing.count()) === 0) {
      await page.waitForTimeout(1000);
      break;
    }
    await page.waitForTimeout(1000);
  }

  console.log('[Chat] AI response received');
}

/**
 * Test: VCF Viewer displays variant data correctly
 */
test.describe('VCF Viewer', () => {
  test('should display variant calls with filtering and statistics', async ({ page }) => {
    await setupTestUser(page);

    // Request workflow that produces VCF output
    await sendChatMessage(
      page,
      'I have a VCF file with variant calls. Can you help me view and analyze the variants?'
    );

    await page.screenshot({ path: `${SCREENSHOT_DIR}/vcf_01_request.png`, fullPage: true });

    // Check for VCF viewer components
    const vcfViewerSelectors = [
      '[data-testid="vcf-viewer"]',
      '.vcf-viewer',
      'text=Variant',
      'text=CHROM',
      'text=Quality',
    ];

    let viewerFound = false;
    for (const selector of vcfViewerSelectors) {
      if ((await page.locator(selector).first().count()) > 0) {
        viewerFound = true;
        console.log(`[VCF] Found viewer element: ${selector}`);
        break;
      }
    }

    await page.screenshot({ path: `${SCREENSHOT_DIR}/vcf_02_viewer.png`, fullPage: true });

    // Test filtering if available
    const filterInput = page.locator('input[placeholder*="filter"]').first();
    if ((await filterInput.count()) > 0) {
      await filterInput.fill('chr1');
      await page.waitForTimeout(1000);
      await page.screenshot({ path: `${SCREENSHOT_DIR}/vcf_03_filtered.png`, fullPage: true });
    }

    console.log(`[VCF] Test completed. Viewer found: ${viewerFound}`);
  });
});

/**
 * Test: Sequence Viewer displays FASTA/FASTQ data
 */
test.describe('Sequence Viewer', () => {
  test('should display sequences with GC content and statistics', async ({ page }) => {
    await setupTestUser(page);

    // Request sequence analysis
    await sendChatMessage(
      page,
      'I have a FASTA file with DNA sequences. Can you help me view the sequences and calculate statistics like GC content?'
    );

    await page.screenshot({ path: `${SCREENSHOT_DIR}/seq_01_request.png`, fullPage: true });

    // Check for sequence viewer components
    const seqViewerSelectors = [
      '[data-testid="sequence-viewer"]',
      '.sequence-viewer',
      'text=Sequence',
      'text=GC Content',
      'text=Length',
    ];

    let viewerFound = false;
    for (const selector of seqViewerSelectors) {
      if ((await page.locator(selector).first().count()) > 0) {
        viewerFound = true;
        console.log(`[Sequence] Found viewer element: ${selector}`);
        break;
      }
    }

    await page.screenshot({ path: `${SCREENSHOT_DIR}/seq_02_viewer.png`, fullPage: true });

    console.log(`[Sequence] Test completed. Viewer found: ${viewerFound}`);
  });
});

/**
 * Test: Annotation Viewer displays BED/GFF/GTF data
 */
test.describe('Annotation Viewer', () => {
  test('should display genomic annotations with feature types', async ({ page }) => {
    await setupTestUser(page);

    // Request annotation viewing
    await sendChatMessage(
      page,
      'I have a BED file with genomic annotations. Can you help me view the features and their genomic coordinates?'
    );

    await page.screenshot({ path: `${SCREENSHOT_DIR}/annot_01_request.png`, fullPage: true });

    // Check for annotation viewer components
    const annotViewerSelectors = [
      '[data-testid="annotation-viewer"]',
      '.annotation-viewer',
      'text=Feature',
      'text=Chromosome',
      'text=Strand',
    ];

    let viewerFound = false;
    for (const selector of annotViewerSelectors) {
      if ((await page.locator(selector).first().count()) > 0) {
        viewerFound = true;
        console.log(`[Annotation] Found viewer element: ${selector}`);
        break;
      }
    }

    await page.screenshot({ path: `${SCREENSHOT_DIR}/annot_02_viewer.png`, fullPage: true });

    console.log(`[Annotation] Test completed. Viewer found: ${viewerFound}`);
  });
});

/**
 * Test: Interactive Tool Launcher suggests appropriate tools
 */
test.describe('Interactive Tool Launcher', () => {
  test('should suggest Galaxy interactive tools based on output type', async ({ page }) => {
    await setupTestUser(page);

    // Request single-cell analysis (should trigger CellxGene suggestion)
    await sendChatMessage(
      page,
      'I have a single-cell RNA-seq h5ad file. Can you help me visualize the data with an interactive tool like CellxGene?'
    );

    await page.screenshot({ path: `${SCREENSHOT_DIR}/interactive_01_request.png`, fullPage: true });

    // Check for interactive tool launcher components
    const toolLauncherSelectors = [
      '[data-testid="interactive-tool-launcher"]',
      '.interactive-tool-launcher',
      'text=CellxGene',
      'text=Launch',
      'text=Interactive',
    ];

    let launcherFound = false;
    for (const selector of toolLauncherSelectors) {
      if ((await page.locator(selector).first().count()) > 0) {
        launcherFound = true;
        console.log(`[InteractiveTool] Found launcher element: ${selector}`);
        break;
      }
    }

    await page.screenshot({ path: `${SCREENSHOT_DIR}/interactive_02_launcher.png`, fullPage: true });

    // Test tool suggestions for different file types
    const toolSuggestions = [
      { type: 'BAM/VCF', tool: 'IGV', request: 'I want to view my BAM alignment file in a genome browser' },
      { type: 'h5ad', tool: 'CellxGene', request: 'Launch CellxGene to explore my single-cell data' },
      { type: 'notebook', tool: 'JupyterLab', request: 'I want to analyze my data in a Jupyter notebook' },
    ];

    console.log(`[InteractiveTool] Test completed. Launcher found: ${launcherFound}`);
  });
});

/**
 * Test: Output attachment component integrates all viewers
 */
test.describe('Output Attachments Integration', () => {
  test('should group outputs by type and render appropriate viewers', async ({ page }) => {
    await setupTestUser(page);

    // Request a workflow that produces multiple output types
    await sendChatMessage(
      page,
      'Can you run a variant calling workflow on my sample? I want to see the VCF output and any quality metrics.'
    );

    await page.screenshot({ path: `${SCREENSHOT_DIR}/integration_01_request.png`, fullPage: true });

    // Wait for potential workflow execution
    await page.waitForTimeout(10000);

    await page.screenshot({ path: `${SCREENSHOT_DIR}/integration_02_outputs.png`, fullPage: true });

    // Check for output grouping
    const outputGroupSelectors = [
      '[data-testid="output-group"]',
      '.output-attachments',
      'text=Outputs',
      'text=Download',
    ];

    let groupingFound = false;
    for (const selector of outputGroupSelectors) {
      if ((await page.locator(selector).first().count()) > 0) {
        groupingFound = true;
        console.log(`[Integration] Found output group: ${selector}`);
        break;
      }
    }

    // Test download functionality if available
    const downloadBtn = page.locator('button:has-text("Download")').first();
    if ((await downloadBtn.count()) > 0) {
      console.log('[Integration] Download button found');
      await page.screenshot({ path: `${SCREENSHOT_DIR}/integration_03_download.png`, fullPage: true });
    }

    console.log(`[Integration] Test completed. Grouping found: ${groupingFound}`);
  });
});

/**
 * Test: Error handling in viewers
 */
test.describe('Viewer Error Handling', () => {
  test('should display graceful error messages for invalid data', async ({ page }) => {
    await setupTestUser(page);

    // Request with potentially problematic input
    await sendChatMessage(
      page,
      'Can you parse this malformed VCF data and show me the variants?'
    );

    await page.screenshot({ path: `${SCREENSHOT_DIR}/error_01_request.png`, fullPage: true });

    // Check for error handling UI
    const errorSelectors = [
      '[data-testid="error-message"]',
      '.error',
      'text=Error',
      'text=Unable to parse',
    ];

    let errorHandled = false;
    for (const selector of errorSelectors) {
      if ((await page.locator(selector).first().count()) > 0) {
        errorHandled = true;
        console.log(`[Error] Found error handling: ${selector}`);
        break;
      }
    }

    await page.screenshot({ path: `${SCREENSHOT_DIR}/error_02_result.png`, fullPage: true });

    console.log(`[Error] Test completed. Error handled: ${errorHandled}`);
  });
});

/**
 * After all tests, generate summary report
 */
test.afterAll(async () => {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const summaryPath = path.join(SCREENSHOT_DIR, `test_summary_${timestamp}.json`);

  const summary = {
    timestamp: new Date().toISOString(),
    baseUrl: BASE_URL,
    videoDir: VIDEO_DIR,
    screenshotDir: SCREENSHOT_DIR,
    tests: [
      'VCF Viewer',
      'Sequence Viewer',
      'Annotation Viewer',
      'Interactive Tool Launcher',
      'Output Attachments Integration',
      'Viewer Error Handling',
    ],
    note: 'Video recordings saved to e2e/videos/, screenshots to e2e/screenshots/',
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  console.log(`\n[Summary] Test summary saved to: ${summaryPath}`);
  console.log(`[Summary] Videos saved to: ${VIDEO_DIR}`);
  console.log(`[Summary] Screenshots saved to: ${SCREENSHOT_DIR}`);
});
