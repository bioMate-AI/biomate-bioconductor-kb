/**
 * Playwright config for publication-quality demo recordings.
 *
 * Matches files ending in *.demo.ts — separate from *.e2e.ts so demos
 * never run in CI and can have video enabled without OOM risk.
 *
 * Run all 5 demos:
 *   npx playwright test --config playwright.demo.config.ts
 *
 * Run a single demo:
 *   npx playwright test --config playwright.demo.config.ts e2e/demo-01-drug-discovery.demo.ts
 *
 * Videos land in e2e/demo-videos/<demo-name>/
 */
import { defineConfig, devices } from '@playwright/test';
import { config as dotenvConfig } from 'dotenv';

dotenvConfig();

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.demo.ts',
  fullyParallel: false,
  workers: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'e2e/demo-reports', open: 'never' }],
    ['json', { outputFile: 'e2e/demo-reports/demo-results.json' }],
  ],

  // 2-hour ceiling per demo (WGS/CryoEM Batch workflows can take 1-2 hours)
  // Individual tests override this with test.setTimeout() when needed.
  timeout: 7_200_000,

  use: {
    baseURL: process.env.BIOMATE_URL || 'http://localhost:5000',

    // Video on — primary output artifact
    // 2560×1440 with deviceScaleFactor:2 renders internally at 5120×2880
    // then downsamples to 2560×1440 — ultra-sharp Retina-quality 1440p output.
    video: {
      mode: 'on',
      size: { width: 2560, height: 1440 },
    },
    screenshot: 'on',
    trace: 'retain-on-failure',  // capture trace on failures for debugging

    viewport: { width: 2560, height: 1440 },
    actionTimeout: 120_000,
    navigationTimeout: 120_000,

    // Rate-limit bypass — must match E2E_TEST_TOKEN in .env
    extraHTTPHeaders: {
      'X-E2E-Test-Token': process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only',
    },
  },

  // Use a fixed named output dir; Playwright cleans it on each full run but
  // individual per-demo runs preserve other demos' artifacts via the named
  // subfolder pattern.  Run scripts copy the .webm to e2e/demo-videos/<name>.webm
  // immediately after each test so they survive the next run's cleanup.
  outputDir: 'e2e/demo-artifacts',

  projects: [
    {
      // Default: all demos except demo-07 — ultra-sharp 1440p output
      name: 'chromium',
      testIgnore: ['**/demo-07-*.demo.ts'],
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 2560, height: 1440 },
        deviceScaleFactor: 2,
      },
    },
    {
      // Demo 07 (CRO Tutorial Tour): 1920×1080 Full HD so the CRO page
      // fills the frame and the video.size matches the viewport exactly.
      // Using the default 2560×1440 with setViewportSize inside the test
      // causes content to render in the top-left and the rest to be blank.
      name: 'chromium-cro',
      testMatch: ['**/demo-07-*.demo.ts'],
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1920, height: 1080 },
        deviceScaleFactor: 1,
        video: {
          mode: 'on',
          size: { width: 1920, height: 1080 },
        },
        screenshot: 'on',
        trace: 'retain-on-failure',
        actionTimeout: 120_000,
        navigationTimeout: 120_000,
        extraHTTPHeaders: {
          'X-E2E-Test-Token': process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only',
        },
      },
    },
  ],
});
