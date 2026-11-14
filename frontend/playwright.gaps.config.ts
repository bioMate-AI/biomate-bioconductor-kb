import { defineConfig, devices } from '@playwright/test';
import { config as dotenvConfig } from 'dotenv';
dotenvConfig();
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/cryoem-panel-sse-gaps.e2e.ts',
  fullyParallel: true,
  workers: 4,
  timeout: 300_000,
  reporter: [['list']],
  use: {
    baseURL: process.env.BIOMATE_URL || 'http://localhost:5000',
    viewport: { width: 1440, height: 900 },
    video: 'off',
    screenshot: 'off',
    actionTimeout: 30_000,      // 30s per interaction (fill, click, etc.)
    navigationTimeout: 30_000,  // 30s per page navigation
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
