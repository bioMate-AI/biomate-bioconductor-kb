import { defineConfig, devices } from '@playwright/test';

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

  use: {
    baseURL: process.env.BIOMATE_URL || 'http://localhost:5000',
    trace: 'on', // Collect trace for all tests
    screenshot: 'on', // Capture screenshots
    video: {
      mode: 'on', // Record video for all tests
      size: { width: 1920, height: 1080 },
    },
    actionTimeout: 30000,
    navigationTimeout: 60000,
  },

  // Output directories (override for isolated runs via PW_OUTPUT_DIR)
  outputDir: process.env.PW_OUTPUT_DIR || 'e2e/test-results',

  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1920, height: 1080 },
      },
    },
    // Optionally add Firefox for cross-browser testing
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] },
    // },
  ],

  // Web server configuration (if starting server with tests)
  // webServer: {
  //   command: 'npm run dev',
  //   url: 'http://localhost:5000',
  //   reuseExistingServer: !process.env.CI,
  //   timeout: 120000,
  // },
});
