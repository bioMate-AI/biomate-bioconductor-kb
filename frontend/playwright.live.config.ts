import { defineConfig, devices } from '@playwright/test';
import { resolveE2eBaseUrl } from './e2e/_e2e-base-url';

/**
 * Live-journey Playwright config (Track E, docs/20261110_LIVE_JOURNEY_TESTS_AND_CI.md).
 *
 * Runs ONLY e2e/live-journeys.e2e.ts against a deployed stack (default: dev).
 * Differences from playwright.config.ts, all deliberate:
 *  - retries: 0  — a journey that only passes on retry is a failing journey, and
 *    every retry re-spends LLM / GPU budget on the shared fixture account.
 *  - one worker; ONE login + ONE project via globalSetup/globalTeardown, so a
 *    failing journey does not skip the independent ones.
 *  - bundled chromium (no `channel: 'chrome'`) so CI and the post-sync hook do
 *    not depend on a system Chrome install. Override with PLAYWRIGHT_CHANNEL.
 *  - 1x device scale (these are audit screenshots, not manual captures).
 */
export default defineConfig({
  testDir: './e2e',
  testMatch: 'live-journeys.e2e.ts',
  // Login once + one project per run, independent of worker restarts.
  globalSetup: './e2e/live-journeys.setup.ts',
  globalTeardown: './e2e/live-journeys.teardown.ts',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  timeout: 10 * 60_000,
  reporter: [
    ['list'],
    ['json', { outputFile: process.env.LIVE_JOURNEYS_JSON || 'e2e/reports/live-journeys.json' }],
  ],
  use: {
    // Precedence: BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > live.
    baseURL: resolveE2eBaseUrl('https://dev-public.biomate.ai'),
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
    actionTimeout: 30_000,
    navigationTimeout: 90_000,
    locale: 'zh-CN',
  },
  outputDir: process.env.PW_OUTPUT_DIR || 'e2e/test-results/live-journeys',
  projects: [
    {
      name: 'live-chromium',
      use: {
        ...devices['Desktop Chrome'],
        channel: process.env.PLAYWRIGHT_CHANNEL || undefined,
        viewport: { width: 1600, height: 1000 },
        deviceScaleFactor: 1,
      },
    },
  ],
});
