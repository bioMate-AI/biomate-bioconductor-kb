import { defineConfig, devices } from '@playwright/test';
import { config as dotenvConfig } from 'dotenv';

// Load .env so E2E_TEST_TOKEN (and other server env vars) are available to tests
dotenvConfig();

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
  retries: process.env.CI ? 1 : 0,
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
    baseURL: process.env.BIOMATE_URL || 'http://localhost:5000',
    trace: 'retain-on-failure',
    screenshot: 'on', // Capture screenshots for every test — audit trail
    video: {
      mode: 'off', // Disabled — video recording causes OOM during long-running cryo-EM tests
      size: { width: 1920, height: 1080 },
    },
    actionTimeout: 60000,
    navigationTimeout: 90000,
    // Bypass global rate limiter for all browser-initiated requests
    extraHTTPHeaders: {
      'X-E2E-Test-Token': process.env.E2E_TEST_TOKEN || 'test-e2e-token-12345',
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
