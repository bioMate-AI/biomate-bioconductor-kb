import { defineConfig, devices } from '@playwright/test';
import { config as dotenvConfig } from 'dotenv';

// Load .env, then .env.local (worktree overrides) if present
dotenvConfig();
dotenvConfig({ path: '.env.local', override: true });

/**
 * Playwright configuration for BioMate E2E tests
 * - Video recording enabled for all tests
 * - Screenshots on failure
 * - Trace collection for debugging
 */
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.e2e.ts', // Match .e2e.ts files
  fullyParallel: false, // Run tests sequentially for audit clarity
  forbidOnly: !!process.env.CI,
  retries: 1,
  workers: 1, // Single worker for audit clarity
  reporter: [
    ['html', { outputFolder: 'e2e/reports' }],
    ['json', { outputFile: 'e2e/reports/results.json' }],
    ['list'],
  ],

  // Per-test timeout: 10 minutes for most tests; CryoEM real-run tests override via test.setTimeout().
  // Playwright uses the MINIMUM of global timeout and test.setTimeout, so set global high enough
  // to not interfere with CryoEM's 45-min real CryoSPARC runs.
  timeout: 2_700_000,

  use: {
    // Precedence: BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > live (must match e2e/_fixture-login.ts).
    baseURL: (
      process.env.BASE_URL ||
      process.env.PLAYWRIGHT_BASE_URL ||
      process.env.BIOMATE_URL ||
      'https://dev-public.biomate.ai'
    ).replace(/\/+$/, ''),
    trace: 'retain-on-failure',
    screenshot: 'on', // Capture screenshots for every test — audit trail
    video: {
      mode: 'off', // Disabled — video recording causes OOM during long-running cryo-EM tests
      size: { width: 1920, height: 1080 },
    },
    actionTimeout: 60000,
    navigationTimeout: 90000,
    // Bypass the global rate limiter for harness traffic. Auth is NOT a header: the
    // browser is authenticated by the biomate_token session cookie (e2e/_fixture-login.ts),
    // which is host-scoped and so never reaches presigned S3 URLs. Default = the dev value
    // of E2E_TEST_TOKEN (CLAUDE.md "Auth header on dev"), same default as _fixture-login.ts.
    extraHTTPHeaders: {
      'X-E2E-Test-Token': process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only',
    },
  },

  // Output directories (override for isolated runs via PW_OUTPUT_DIR)
  outputDir: process.env.PW_OUTPUT_DIR || 'e2e/test-results',

  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        // Use system Chrome when available (set via PLAYWRIGHT_CHANNEL=chrome).
        // The bundled headless_shell (chromium-1200+) requires macOS 12+
        // and crashes with "AVFAudio not loaded" on Big Sur (macOS 11).
        // On aarch64 Linux hosts (AWS EC2/Docker), leave channel=undefined so
        // Playwright uses its bundled arm64 chromium — system Chrome is x86_64
        // there and would run under qemu emulation, crashing the GPU process.
        channel: process.env.PLAYWRIGHT_CHANNEL || (process.platform === 'darwin' ? 'chrome' : undefined),
        viewport: { width: 1920, height: 1080 },
        // HIGH-RES manual/doc screenshots: force 2x (retina) pixel density so
        // captures are crisp regardless of host display (headless EC2 = 1x
        // otherwise). A 1440-wide viewport thus yields a 2880px PNG.
        deviceScaleFactor: 2,
      },
    },
    {
      name: 'demo',
      testMatch: '**/*.demo.ts',
      outputDir: 'e2e/demo-artifacts',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1920, height: 1080 },
        video: {
          mode: 'on',
          size: { width: 1920, height: 1080 },
        },
      },
    },
    {
      name: 'firefox',
      testMatch: '**/*.e2e.ts',
      use: {
        ...devices['Desktop Firefox'],
        viewport: { width: 1920, height: 1080 },
        deviceScaleFactor: 2, // HIGH-RES: match chromium — 2x retina PNGs (no video on this project, so safe)
      },
    },
  ],

  // Web server configuration (if starting server with tests)
  // webServer: {
  //   command: 'npm run dev',
  //   url: 'http://localhost:5000',
  //   reuseExistingServer: !process.env.CI,
  //   timeout: 120000,
  // },
});
