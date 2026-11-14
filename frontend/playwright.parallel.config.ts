import { defineConfig, devices } from '@playwright/test';
import { config as dotenvConfig } from 'dotenv';
dotenvConfig();
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/cryoem-full-20img-multigpu.e2e.ts',
  fullyParallel: true,
  workers: 4,
  timeout: 28_800_000,
  reporter: [['list']],
  use: {
    baseURL: process.env.BIOMATE_URL || 'http://localhost:5000',
    viewport: { width: 1440, height: 900 },
    video: 'off',
    screenshot: 'off',
    actionTimeout: 30_000,
    navigationTimeout: 60_000,  // 60s for slower AWS-backed pages
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
