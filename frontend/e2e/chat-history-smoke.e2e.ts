/**
 * Chat History Smoke Test
 *
 * Verifies:
 *  1. Sessions API returns 200 for authenticated user (JWT re-signing works)
 *  2. Session detail endpoint returns full messages
 *  3. Clearing localStorage and reloading restores sessions from backend
 *  4. New chat message is persisted to backend
 *
 * NO MOCKS — hits live backend.
 */
import { test, expect } from "@playwright/test";
import { BASE_URL } from "./helpers.js";

test.setTimeout(90000);

const TEST_EMAIL = "billing-smoke@biomate.test";
const TEST_PASS  = "SmokeTest2026!";

async function loginAndGetToken(request: any): Promise<string> {
  const res = await request.post(`${BASE_URL}/api/auth/login`, {
    data: { email: TEST_EMAIL, password: TEST_PASS },
  });
  expect(res.status()).toBe(200);
  const { token } = await res.json();
  expect(token).toBeTruthy();
  return token;
}

async function doLogin(page: any): Promise<void> {
  await page.goto(`${BASE_URL}/login`);
  await page.fill('input[type="email"]', TEST_EMAIL);
  await page.fill('input[type="password"]', TEST_PASS);
  await page.click('button[type="submit"]');
  // Login may redirect to /dashboard or /
  await page.waitForURL(/\/(dashboard|$)/, { timeout: 20000 });
  // Navigate to chat platform
  await page.goto(`${BASE_URL}/`);
  await page.waitForLoadState("networkidle", { timeout: 10000 });
}

test.describe("Chat History Sync", () => {
  test("sessions API returns 200 for authenticated user", async ({ request }) => {
    const token = await loginAndGetToken(request);

    const sessionsRes = await request.get(`${BASE_URL}/api/sessions?limit=20`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(sessionsRes.status(), "GET /api/sessions should return 200 (JWT re-signing fix)").toBe(200);
    const sessions = await sessionsRes.json();
    expect(Array.isArray(sessions), "Sessions response should be an array").toBeTruthy();

    if (sessions.length > 0) {
      const s = sessions[0];
      expect(s.session_id).toBeTruthy();
      expect(s.title).toBeTruthy();
      expect(s.last_activity).toBeTruthy();
    }
  });

  test("session detail endpoint returns messages", async ({ request }) => {
    const token = await loginAndGetToken(request);

    const listRes = await request.get(`${BASE_URL}/api/sessions?limit=5`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(listRes.status()).toBe(200);
    const sessions = await listRes.json();

    if (!Array.isArray(sessions) || sessions.length === 0) {
      test.skip();
      return;
    }

    const sessionId = sessions[0].session_id;
    const detailRes = await request.get(`${BASE_URL}/api/sessions/${sessionId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(detailRes.status(), "GET /api/sessions/:id should return 200").toBe(200);
    const detail = await detailRes.json();
    expect(detail.session_id).toBe(sessionId);
    expect(Array.isArray(detail.messages), "Detail should include messages array").toBeTruthy();
  });

  test("cross-machine: clearing localStorage restores sessions from backend", async ({ page, request }) => {
    await doLogin(page);

    // Wait for initial backend sync (2s debounce + network)
    await page.waitForTimeout(5000);

    // Confirm backend has sessions
    const token = await loginAndGetToken(request);
    const sessionsRes = await request.get(`${BASE_URL}/api/sessions?limit=20`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(sessionsRes.status()).toBe(200);
    const backendSessions = await sessionsRes.json();

    // Simulate different machine: wipe localStorage chat history
    await page.evaluate(() => {
      localStorage.removeItem('biomate-chat-history');
    });

    // Reload (auth cookies still active — simulates same account, different machine)
    await page.reload();
    await page.waitForLoadState("networkidle", { timeout: 10000 });

    // Wait for backend pull
    await page.waitForTimeout(5000);

    if (Array.isArray(backendSessions) && backendSessions.length > 0) {
      // localStorage should be repopulated from backend
      const restored = await page.evaluate(() => {
        const raw = localStorage.getItem('biomate-chat-history');
        return raw ? JSON.parse(raw) : [];
      });
      expect(
        restored.length,
        `Sessions should be restored from backend (backend has ${backendSessions.length})`
      ).toBeGreaterThan(0);
    }
  });

  test("new message is synced to backend and retrievable", async ({ page, request }) => {
    await doLogin(page);

    // Send a short message
    const msgInput = page.locator('[data-testid="chat-input"], textarea').first();
    await expect(msgInput).toBeVisible({ timeout: 10000 });
    await msgInput.fill('history sync test ping');
    await msgInput.press('Enter');

    // Wait for LLM response + 2s debounce sync
    await page.waitForTimeout(10000);

    // Query backend
    const token = await loginAndGetToken(request);
    const sessionsRes = await request.get(`${BASE_URL}/api/sessions?limit=20`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(sessionsRes.status()).toBe(200);
    const sessions = await sessionsRes.json();
    expect(Array.isArray(sessions)).toBeTruthy();
    expect(sessions.length, "At least one session should be stored on backend").toBeGreaterThan(0);

    // Fetch detail of most recent session and check it has messages
    const latestId = sessions[0].session_id;
    const detailRes = await request.get(`${BASE_URL}/api/sessions/${latestId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(detailRes.status()).toBe(200);
    const detail = await detailRes.json();
    expect(detail.messages.length, "Session should have messages stored").toBeGreaterThan(0);
  });
});
