import { test, expect } from "@playwright/test";
import * as path from "path";
import { fileURLToPath } from "url";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5421";
const LOGIN_EMAIL = process.env.BIOMATE_E2E_EMAIL || "e2e_upload@biomate.test";
const LOGIN_PASSWORD = process.env.BIOMATE_E2E_PASSWORD || "TestPass123!";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REAL_FASTQ_PATH = path.resolve(
  __dirname,
  "../../research/galaxy/test-data/1.fastq"
);

test.setTimeout(120000);

test.describe("Real Data Upload Through Chat", () => {
  test("uploads a real FASTQ file and proceeds through BioMate", async ({ page }) => {
    const uploadResponses: Array<{ status: number; body: any }> = [];
    const chatStreamStatuses: number[] = [];

    page.on("response", async (response) => {
      if (response.url().includes("/api/chat/stream")) {
        chatStreamStatuses.push(response.status());
      }
      if (!response.url().includes("/api/datasets/upload")) {
        return;
      }
      let body: any = null;
      try {
        body = await response.json();
      } catch {
        body = null;
      }
      uploadResponses.push({ status: response.status(), body });
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState("networkidle");
    const authResult = await page.evaluate(
      async ({ email, password }) => {
        const login = await fetch("/api/auth/login", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "include",
          body: JSON.stringify({ email, password }),
        });
        if (login.ok) {
          return { ok: true, step: "login" };
        }

        const register = await fetch("/api/auth/register", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "include",
          body: JSON.stringify({
            fullName: "E2E Upload User",
            email,
            password,
            termsAccepted: true,
          }),
        });
        if (register.ok) {
          return { ok: true, step: "register" };
        }

        let loginBody: any = null;
        let registerBody: any = null;
        try {
          loginBody = await login.json();
        } catch {
          loginBody = null;
        }
        try {
          registerBody = await register.json();
        } catch {
          registerBody = null;
        }
        return {
          ok: false,
          loginStatus: login.status,
          loginBody,
          registerStatus: register.status,
          registerBody,
        };
      },
      { email: LOGIN_EMAIL, password: LOGIN_PASSWORD }
    );
    // If registration is rate-limited in shared environments, continue and rely on
    // the upload endpoint assertion below to prove the real E2E auth state.
    const registrationRateLimited =
      authResult?.registerStatus === 429 && authResult?.registerBody?.error === "REGISTRATION_LIMIT_EXCEEDED";
    if (!authResult.ok && !registrationRateLimited) {
      expect(authResult.ok, `Auth setup failed: ${JSON.stringify(authResult)}`).toBeTruthy();
    }

    let chatInput = page.getByTestId("chat-input");
    if (!(await chatInput.isVisible().catch(() => false))) {
      chatInput = page.locator("textarea").first();
    }
    await expect(chatInput).toBeVisible({ timeout: 15000 });

    const composer = page.locator("div.border-t").last();
    await composer.locator("button").first().click();
    await expect(page.getByRole("button", { name: /choose files/i })).toBeVisible({ timeout: 10000 });
    await page.setInputFiles("#chat-file-input", REAL_FASTQ_PATH);

    await expect(page.getByText("1.fastq")).toBeVisible({ timeout: 10000 });

    const userPrompt =
      "I uploaded a real FASTQ file. Build a runnable QC workflow and explain what you will do.";
    await chatInput.fill(userPrompt);
    await page.getByTestId("chat-send-button").click();

    await expect.poll(() => uploadResponses.length, { timeout: 30000 }).toBeGreaterThan(0);
    const successfulUpload = uploadResponses.find((r) => r.status === 200);
    expect(successfulUpload, `Upload responses: ${JSON.stringify(uploadResponses)} (auth=${JSON.stringify(authResult)})`).toBeTruthy();
    expect(successfulUpload?.body?.dataset_id).toBeTruthy();

    await expect(page.getByText(/\[Uploaded datasets:/i)).toBeVisible({ timeout: 20000 });

    await page
      .waitForSelector("text=AI is typing", { timeout: 10000 })
      .catch(() => undefined);
    await page
      .waitForSelector("text=AI is typing", { state: "hidden", timeout: 120000 })
      .catch(() => undefined);

    expect(chatStreamStatuses.some((status) => status >= 200 && status < 300)).toBe(true);
  });
});
