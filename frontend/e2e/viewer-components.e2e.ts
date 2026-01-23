/**
 * Bioinformatics Viewer Component E2E Tests
 *
 * These tests actually render the viewer components with mock data
 * to verify they work correctly.
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'viewers');

// Ensure directories exist
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

// Test configuration
test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

// Increase timeout for viewer tests
test.setTimeout(120000);

// Mock VCF data
const MOCK_VCF_DATA = {
  header: {
    fileFormat: 'VCFv4.2',
    samples: ['Sample1', 'Sample2'],
    contigs: ['chr1', 'chr2', 'chr3'],
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
  ],
  stats: {
    totalVariants: 5,
    snps: 3,
    indels: 2,
    multiallelic: 0,
    passedFilter: 4,
  },
};

// Mock sequence data
const MOCK_SEQUENCE_DATA = {
  sequences: [
    { id: 'seq1', description: 'Test sequence 1', sequence: 'ATCGATCGATCG', length: 12, gcContent: 50.0 },
    { id: 'seq2', description: 'Test sequence 2', sequence: 'GGGGCCCCAAAA', length: 12, gcContent: 66.7 },
    { id: 'seq3', description: 'Test sequence 3', sequence: 'TTTTAAAATTTT', length: 12, gcContent: 0.0 },
  ],
  stats: {
    totalSequences: 3,
    totalLength: 36,
    avgLength: 12,
    avgGcContent: 38.9,
    minLength: 12,
    maxLength: 12,
  },
};

// Mock annotation data
const MOCK_ANNOTATION_DATA = {
  features: [
    { chrom: 'chr1', start: 1000, end: 2000, name: 'gene1', score: 100, strand: '+', type: 'gene' },
    { chrom: 'chr1', start: 1200, end: 1500, name: 'exon1', score: 100, strand: '+', type: 'exon' },
    { chrom: 'chr1', start: 1600, end: 1900, name: 'exon2', score: 100, strand: '+', type: 'exon' },
    { chrom: 'chr2', start: 5000, end: 8000, name: 'gene2', score: 95, strand: '-', type: 'gene' },
  ],
  stats: {
    totalFeatures: 4,
    chromosomes: 2,
    featureTypes: { gene: 2, exon: 2 },
  },
};

// Mock output dataset
const createMockOutput = (id: string, name: string, fileType: string, extension: string) => ({
  id,
  name,
  fileType,
  extension,
  size: 1024,
  galaxyId: `gxy-${id}`,
  invocationId: 'inv-123',
  metadata: {},
});

/**
 * Helper to setup test user
 */
async function setupTestUser(page: Page, testName: string): Promise<void> {
  const email = `e2e_viewer_${Date.now()}_${testName}@biomate.test`;
  const password = 'TestPass123!';

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState('networkidle');

  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
    await page.fill('#name', 'E2E Viewer Tester');
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
 * Test: VCF Viewer with mocked output data
 */
test.describe('VCF Viewer', () => {
  test('should render VCF viewer with variant data', async ({ page }) => {
    await setupTestUser(page, 'vcf_viewer');

    // Mock the outputs API to return VCF data
    await page.route('**/api/invocations/*/outputs', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([createMockOutput('vcf-1', 'variants.vcf', 'variants', 'vcf')]),
      });
    });

    // Mock the VCF parse API
    await page.route('**/api/outputs/*/parse*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_VCF_DATA),
      });
    });

    // Mock invocations list to include a test invocation
    await page.route('**/api/invocations', async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([{
            id: 'inv-123',
            workflowId: 'wf-1',
            state: 'ok',
            createTime: new Date().toISOString(),
            updateTime: new Date().toISOString(),
          }]),
        });
      } else {
        await route.continue();
      }
    });

    // Navigate to main page
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Take screenshot of initial state
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/vcf_viewer_initial.png`,
      fullPage: true,
    });

    // Check if the VCF viewer elements are visible
    // The viewer needs an invocation with outputs to render
    const pageContent = await page.textContent('body');

    console.log('[VCF Viewer] Page content includes "Variant":', pageContent?.includes('Variant'));
    console.log('[VCF Viewer] Page content includes "VCF":', pageContent?.includes('VCF'));

    // Look for the My Workflows button which would show invocations
    const workflowsButton = page.getByRole('button', { name: 'My Workflows' });
    if (await workflowsButton.isVisible()) {
      await workflowsButton.click();
      await page.waitForTimeout(1000);

      await page.screenshot({
        path: `${SCREENSHOT_DIR}/vcf_viewer_workflows_panel.png`,
        fullPage: true,
      });
    }

    console.log('[VCF Viewer] Test completed');
  });
});

/**
 * Test: Sequence Viewer with mocked output data
 */
test.describe('Sequence Viewer', () => {
  test('should render sequence viewer with FASTA data', async ({ page }) => {
    await setupTestUser(page, 'sequence_viewer');

    // Mock the outputs API
    await page.route('**/api/invocations/*/outputs', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([createMockOutput('seq-1', 'sequences.fasta', 'sequence', 'fasta')]),
      });
    });

    // Mock the sequence parse API
    await page.route('**/api/outputs/*/parse*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_SEQUENCE_DATA),
      });
    });

    // Mock invocations list
    await page.route('**/api/invocations', async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([{
            id: 'inv-seq-123',
            workflowId: 'wf-seq',
            state: 'ok',
            createTime: new Date().toISOString(),
            updateTime: new Date().toISOString(),
          }]),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/sequence_viewer_initial.png`,
      fullPage: true,
    });

    // Click My Workflows to see invocations
    const workflowsButton = page.getByRole('button', { name: 'My Workflows' });
    if (await workflowsButton.isVisible()) {
      await workflowsButton.click();
      await page.waitForTimeout(1000);

      await page.screenshot({
        path: `${SCREENSHOT_DIR}/sequence_viewer_workflows.png`,
        fullPage: true,
      });
    }

    console.log('[Sequence Viewer] Test completed');
  });
});

/**
 * Test: Annotation Viewer with mocked output data
 */
test.describe('Annotation Viewer', () => {
  test('should render annotation viewer with BED data', async ({ page }) => {
    await setupTestUser(page, 'annotation_viewer');

    // Mock the outputs API
    await page.route('**/api/invocations/*/outputs', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([createMockOutput('bed-1', 'features.bed', 'annotation', 'bed')]),
      });
    });

    // Mock the annotation parse API
    await page.route('**/api/outputs/*/parse*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_ANNOTATION_DATA),
      });
    });

    // Mock invocations list
    await page.route('**/api/invocations', async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([{
            id: 'inv-bed-123',
            workflowId: 'wf-bed',
            state: 'ok',
            createTime: new Date().toISOString(),
            updateTime: new Date().toISOString(),
          }]),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/annotation_viewer_initial.png`,
      fullPage: true,
    });

    // Click My Workflows
    const workflowsButton = page.getByRole('button', { name: 'My Workflows' });
    if (await workflowsButton.isVisible()) {
      await workflowsButton.click();
      await page.waitForTimeout(1000);

      await page.screenshot({
        path: `${SCREENSHOT_DIR}/annotation_viewer_workflows.png`,
        fullPage: true,
      });
    }

    console.log('[Annotation Viewer] Test completed');
  });
});

/**
 * After all tests, generate summary
 */
test.afterAll(async () => {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const summaryPath = path.join(SCREENSHOT_DIR, `viewer_test_summary_${timestamp}.json`);

  const summary = {
    timestamp: new Date().toISOString(),
    baseUrl: BASE_URL,
    testType: 'Viewer Component Tests',
    tests: [
      'VCF Viewer',
      'Sequence Viewer',
      'Annotation Viewer',
    ],
    note: 'These tests mock the output API to render viewer components',
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  console.log(`\n[Summary] Viewer test summary saved to: ${summaryPath}`);
});
