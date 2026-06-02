/**
 * Playwright config for cryo tutorial recording.
 * Uses system Chrome (channel: 'chrome') to avoid the headless shell
 * AVFAudio framework issue on macOS 11.
 */
import { defineConfig } from '@playwright/test';
import { config as dotenvConfig } from 'dotenv';

dotenvConfig();

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/cryo-tutorial-research-ui.demo.ts',
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  timeout: 600_000,

  use: {
    channel: 'chrome',
    headless: true,
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 2,
    video: {
      mode: 'on',
      size: { width: 1920, height: 1080 },
    },
    screenshot: 'on',
    trace: 'retain-on-failure',
    actionTimeout: 60_000,
    navigationTimeout: 60_000,
  },

  outputDir: 'e2e/demo-artifacts',
});
