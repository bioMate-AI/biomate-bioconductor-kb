import { defineConfig, devices } from "@playwright/test";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

// Standalone Playwright config for the sandbox port smoke tests.
// Uses a sandbox-local output dir to avoid the root-owned
// frontend/e2e/test-results from prior Docker runs.
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export default defineConfig({
  testDir: __dirname,
  testMatch: /(smoke|screenshot|tiptap|structural)\.test\.ts$/,
  outputDir: __dirname + "/.test-output",
  reporter: [["list"]],
  use: {
    baseURL: "http://localhost:7791",
    ...devices["Desktop Chrome"],
  },
  // Vite is already running on :7791 — no webServer block.
  workers: 1,
  retries: 0,
});
