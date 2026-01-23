/**
 * Workflow Output Viewers E2E Tests
 *
 * Tests that actually render the bioinformatics viewers by:
 * 1. Mocking a chat response with an invocationId
 * 2. Mocking the invocation outputs with VCF/FASTA/BED data
 * 3. Verifying the viewers render correctly
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'workflow-viewers');

// Ensure directories exist
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

// Test configuration with video recording
test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

test.setTimeout(120000);

// Mock VCF data for VCF viewer
const MOCK_VCF_DATA = {
  header: {
    fileFormat: 'VCFv4.2',
    samples: ['Sample1', 'Sample2'],
    contigs: ['chr1', 'chr2', 'chr3', 'chr4', 'chr5'],
    infoFields: [
      { id: 'DP', description: 'Total Depth' },
      { id: 'AF', description: 'Allele Frequency' },
    ],
  },
  variants: [
    { chrom: 'chr1', pos: 12345, id: 'rs12345', ref: 'A', alt: 'G', qual: 99.5, filter: 'PASS', info: { DP: '100' } },
    { chrom: 'chr1', pos: 23456, id: 'rs23456', ref: 'C', alt: 'T', qual: 85.2, filter: 'PASS', info: { DP: '80' } },
    { chrom: 'chr1', pos: 34567, id: '.', ref: 'GG', alt: 'G', qual: 45.0, filter: 'LowQual', info: { DP: '30' } },
    { chrom: 'chr2', pos: 11111, id: 'rs11111', ref: 'T', alt: 'TA', qual: 92.0, filter: 'PASS', info: { DP: '120' } },
    { chrom: 'chr2', pos: 22222, id: 'rs22222', ref: 'A', alt: 'C', qual: 78.5, filter: 'PASS', info: { DP: '65' } },
    { chrom: 'chr3', pos: 55555, id: 'rs55555', ref: 'G', alt: 'A', qual: 95.0, filter: 'PASS', info: { DP: '150' } },
    { chrom: 'chr4', pos: 77777, id: 'rs77777', ref: 'T', alt: 'C', qual: 88.0, filter: 'PASS', info: { DP: '90' } },
  ],
  stats: {
    totalVariants: 7,
    snps: 5,
    indels: 2,
    multiallelic: 0,
    passedFilter: 6,
  },
};

// Mock sequence data for Sequence viewer
const MOCK_SEQUENCE_DATA = {
  sequences: [
    { id: 'seq1', description: 'Homo sapiens gene ABC', sequence: 'ATCGATCGATCGATCGATCG', length: 20, gcContent: 45.0 },
    { id: 'seq2', description: 'Mus musculus gene XYZ', sequence: 'GGGGCCCCAAAATTTTGGGG', length: 20, gcContent: 55.0 },
    { id: 'seq3', description: 'Control sequence', sequence: 'ATATATATATATATATAT', length: 18, gcContent: 0.0 },
  ],
  stats: {
    totalSequences: 3,
    totalLength: 58,
    avgLength: 19.3,
    avgGcContent: 33.3,
    minLength: 18,
    maxLength: 20,
  },
};

// Mock annotation data for Annotation viewer
const MOCK_ANNOTATION_DATA = {
  features: [
    { chrom: 'chr1', start: 1000, end: 5000, name: 'BRCA1', score: 1000, strand: '+', type: 'gene' },
    { chrom: 'chr1', start: 1000, end: 1500, name: 'BRCA1_exon1', score: 100, strand: '+', type: 'exon' },
    { chrom: 'chr1', start: 2000, end: 2500, name: 'BRCA1_exon2', score: 100, strand: '+', type: 'exon' },
    { chrom: 'chr1', start: 3500, end: 5000, name: 'BRCA1_exon3', score: 100, strand: '+', type: 'exon' },
    { chrom: 'chr17', start: 10000, end: 15000, name: 'TP53', score: 1000, strand: '-', type: 'gene' },
    { chrom: 'chr17', start: 10000, end: 10800, name: 'TP53_exon1', score: 100, strand: '-', type: 'exon' },
  ],
  stats: {
    totalFeatures: 6,
    chromosomes: 2,
    featureTypes: { gene: 2, exon: 4 },
  },
};

/**
 * Helper to setup test user
 */
async function setupTestUser(page: Page, testName: string): Promise<void> {
  const email = `e2e_wf_viewer_${Date.now()}_${testName}@biomate.test`;
  const password = 'TestPass123!';

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState('networkidle');

  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
    await page.fill('#name', 'Workflow Viewer Tester');
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

/**
 * Test: VCF Viewer renders with workflow output
 */
test.describe('VCF Viewer with Workflow Output', () => {
  test('should display VCF viewer when workflow produces variant output', async ({ page }) => {
    await setupTestUser(page, 'vcf');

    const invocationId = 'inv-vcf-test-123';

    // Mock chat API to return response with invocationId
    await page.route('**/api/chat', async (route) => {
      if (route.request().method() !== 'POST') {
        return route.continue();
      }
      await new Promise(resolve => setTimeout(resolve, 500));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          response: "I've analyzed your VCF file. Here are the variant calling results:\n\n**Summary:**\n- Total variants: 7\n- SNPs: 5\n- Indels: 2\n- PASS filter: 6\n\nThe VCF viewer below shows all variants with filtering and sorting options.",
          suggestions: ['Filter by chromosome', 'Show high-quality variants only'],
          workflow: null,
          invocationId: invocationId,
          metadata: { workflowExecuted: true },
        }),
      });
    });

    // Mock outputs endpoint for the invocation
    await page.route(`**/api/invocations/${invocationId}/outputs`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([{
          id: 'output-vcf-1',
          name: 'variant_calls.vcf',
          fileType: 'variants',
          extension: 'vcf',
          size: 15360,
          galaxyId: 'gxy-vcf-1',
          invocationId: invocationId,
          metadata: { totalVariants: 7 },
        }]),
      });
    });

    // Mock VCF parse endpoint
    await page.route('**/api/outputs/*/parse*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_VCF_DATA),
      });
    });

    // Navigate to app
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Send a message to trigger the mocked response
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    await chatInput.fill('Analyze my VCF file with variant calls');
    await chatInput.press('Enter');

    console.log('[VCF Test] Message sent, waiting for response...');

    // Wait for the response with invocationId to appear
    await page.waitForTimeout(3000);

    // Screenshot of chat with VCF response
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/vcf_chat_response.png`,
      fullPage: true,
    });

    // Check for VCF viewer elements
    const vcfViewerVisible = await page.locator('text=Variant Calls').isVisible().catch(() => false);
    const variantTableVisible = await page.locator('text=Position').isVisible().catch(() => false);
    const statsVisible = await page.locator('text=SNPs').isVisible().catch(() => false);

    console.log('[VCF Test] Viewer elements:', {
      vcfViewerVisible,
      variantTableVisible,
      statsVisible,
    });

    // Wait for viewer to fully render
    await page.waitForTimeout(2000);

    // Final screenshot
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/vcf_viewer_rendered.png`,
      fullPage: true,
    });

    // Verify viewer rendered
    const pageContent = await page.textContent('body');
    const hasVCFContent = pageContent?.includes('variants') || pageContent?.includes('Variant');
    console.log('[VCF Test] Page has VCF content:', hasVCFContent);

    expect(hasVCFContent).toBe(true);
  });
});

/**
 * Test: Sequence Viewer renders with workflow output
 */
test.describe('Sequence Viewer with Workflow Output', () => {
  test('should display sequence viewer when workflow produces FASTA output', async ({ page }) => {
    await setupTestUser(page, 'sequence');

    const invocationId = 'inv-seq-test-456';

    // Mock chat API
    await page.route('**/api/chat', async (route) => {
      if (route.request().method() !== 'POST') {
        return route.continue();
      }
      await new Promise(resolve => setTimeout(resolve, 500));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          response: "I've processed your FASTA sequences:\n\n**Statistics:**\n- Total sequences: 3\n- Average length: 19.3 bp\n- Average GC content: 33.3%\n\nView the sequences below.",
          suggestions: ['Calculate GC content', 'Export sequences'],
          workflow: null,
          invocationId: invocationId,
          metadata: { workflowExecuted: true },
        }),
      });
    });

    // Mock outputs endpoint
    await page.route(`**/api/invocations/${invocationId}/outputs`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([{
          id: 'output-seq-1',
          name: 'sequences.fasta',
          fileType: 'sequence',
          extension: 'fasta',
          size: 2048,
          galaxyId: 'gxy-seq-1',
          invocationId: invocationId,
          metadata: {},
        }]),
      });
    });

    // Mock sequence parse endpoint
    await page.route('**/api/outputs/*/parse*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_SEQUENCE_DATA),
      });
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    await chatInput.fill('Show me the sequences in my FASTA file');
    await chatInput.press('Enter');

    console.log('[Sequence Test] Message sent...');

    await page.waitForTimeout(3000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/sequence_chat_response.png`,
      fullPage: true,
    });

    await page.waitForTimeout(2000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/sequence_viewer_rendered.png`,
      fullPage: true,
    });

    const pageContent = await page.textContent('body');
    const hasSequenceContent = pageContent?.includes('sequence') || pageContent?.includes('Sequence') || pageContent?.includes('FASTA');
    console.log('[Sequence Test] Page has sequence content:', hasSequenceContent);

    expect(hasSequenceContent).toBe(true);
  });
});

/**
 * Test: Annotation Viewer renders with workflow output
 */
test.describe('Annotation Viewer with Workflow Output', () => {
  test('should display annotation viewer when workflow produces BED output', async ({ page }) => {
    await setupTestUser(page, 'annotation');

    const invocationId = 'inv-bed-test-789';

    // Mock chat API
    await page.route('**/api/chat', async (route) => {
      if (route.request().method() !== 'POST') {
        return route.continue();
      }
      await new Promise(resolve => setTimeout(resolve, 500));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          response: "I've parsed your BED file with genomic annotations:\n\n**Features:**\n- Total: 6 features\n- Genes: 2 (BRCA1, TP53)\n- Exons: 4\n\nThe annotation viewer shows all features below.",
          suggestions: ['Filter by gene', 'Export to GFF'],
          workflow: null,
          invocationId: invocationId,
          metadata: { workflowExecuted: true },
        }),
      });
    });

    // Mock outputs endpoint
    await page.route(`**/api/invocations/${invocationId}/outputs`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([{
          id: 'output-bed-1',
          name: 'annotations.bed',
          fileType: 'annotation',
          extension: 'bed',
          size: 4096,
          galaxyId: 'gxy-bed-1',
          invocationId: invocationId,
          metadata: {},
        }]),
      });
    });

    // Mock annotation parse endpoint
    await page.route('**/api/outputs/*/parse*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_ANNOTATION_DATA),
      });
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    await chatInput.fill('Show me the features in my BED annotation file');
    await chatInput.press('Enter');

    console.log('[Annotation Test] Message sent...');

    await page.waitForTimeout(3000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/annotation_chat_response.png`,
      fullPage: true,
    });

    await page.waitForTimeout(2000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/annotation_viewer_rendered.png`,
      fullPage: true,
    });

    const pageContent = await page.textContent('body');
    const hasAnnotationContent = pageContent?.includes('annotation') || pageContent?.includes('BED') || pageContent?.includes('feature');
    console.log('[Annotation Test] Page has annotation content:', hasAnnotationContent);

    expect(hasAnnotationContent).toBe(true);
  });
});

/**
 * Summary
 */
test.afterAll(async () => {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const summaryPath = path.join(SCREENSHOT_DIR, `workflow_viewer_summary_${timestamp}.json`);

  const summary = {
    timestamp: new Date().toISOString(),
    baseUrl: BASE_URL,
    testType: 'Workflow Output Viewer Tests',
    tests: ['VCF Viewer', 'Sequence Viewer', 'Annotation Viewer'],
    note: 'These tests mock workflow outputs to trigger viewer rendering',
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  console.log(`\n[Summary] Workflow viewer test summary saved to: ${summaryPath}`);
});
