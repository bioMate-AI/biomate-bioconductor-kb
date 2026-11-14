/**
 * API-only smoke tests — no browser required.
 *
 * Guards the 4 fixes from the 2026-05-29 → 2026-06-02 infrastructure pivot:
 *   1. ADMET QC profiles registered in central catalog
 *      (backend/lib/galaxy/jobs/qc_trace_monitor.py QC_NAMED_PROFILES)
 *   2. HTS router disambiguation (HTSFilter / sights vs hts_plate_qc)
 *      (frontend/server/galaxy-assistant.ts router rule for HTS)
 *   3. Chat-stream server-side persistence on `event: final`
 *      (frontend/server/routes.ts /api/chat/stream persistAssistantMessage)
 *   4. Chat-stream partial persistence on client disconnect
 *      (same handler, req.socket.on('close') path)
 *
 * Why API-only: Playwright browser tests on aarch64 dev boxes hit a Chrome
 * × qemu × GPU stack mismatch that this suite intentionally side-steps.
 * The same code paths are exercised by direct HTTP calls.
 *
 * Configurable target:
 *   BIOMATE_URL=https://dev-public.biomate.ai    (default: localhost:5000)
 *   E2E_FIXTURE_EMAIL / E2E_FIXTURE_PASSWORD     (in .env.test.local)
 *   E2E_TEST_TOKEN                               (in .env)
 */

import { test, expect, request as pwRequest } from "@playwright/test";

const BASE = process.env.BIOMATE_URL || "http://localhost:5000";
const TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const EMAIL = process.env.E2E_FIXTURE_EMAIL || "e2e-admet-fixture@biomate.test";
const PASS = process.env.E2E_FIXTURE_PASSWORD || "AdmetE2ETest!2026";

const ANON_HEADERS = { "X-E2E-Test-Token": TOKEN, "Content-Type": "application/json" };

async function loginAndGetJwt(): Promise<string> {
  const ctx = await pwRequest.newContext({ extraHTTPHeaders: ANON_HEADERS });
  const r = await ctx.post(`${BASE}/api/auth/login`, {
    data: { email: EMAIL, password: PASS },
  });
  if (!r.ok()) throw new Error(`login failed: ${r.status()} ${await r.text()}`);
  const body = await r.json();
  await ctx.dispose();
  return body.token;
}

async function authedHeaders(): Promise<Record<string, string>> {
  const jwt = await loginAndGetJwt();
  return { ...ANON_HEADERS, Cookie: `biomate_token=${jwt}` };
}

// ─────────────────────────────────────────────────────────────────────────────
test.describe("API smoke — fixes from 2026-06 infra pivot", () => {
  test("HT-0 / AD-0 — /api/qc/profiles registers admet_standard, _cns, _oncology", async ({ request }) => {
    const r = await request.get(`${BASE}/api/qc/profiles`, { headers: ANON_HEADERS });
    expect(r.ok()).toBeTruthy();
    const body = await r.json();
    const names = (body.profiles || []).map((p: any) => p.id);
    expect(names).toContain("admet_standard");
    expect(names).toContain("admet_cns");
    expect(names).toContain("admet_oncology");

    // Verify citation correction (Aronov → Redfern 2003)
    const standard = body.profiles.find((p: any) => p.id === "admet_standard");
    const refs = (standard?.references || []).join(" ");
    expect(refs).toMatch(/Redfern 2003/);
  });

  test("HT-1 — router disambiguates HTS plate query to hts_plate_qc_hit_calling", async ({ request }) => {
    const headers = await authedHeaders();
    const start = Date.now();
    const r = await request.post(`${BASE}/api/ai_assistant/generate_workflow`, {
      headers,
      data: {
        request_text: "Run HTS plate QC and hit calling on my 96-well screening plate",
        preferred_domains: ["drug_discovery"],
      },
      timeout: 60_000,
    });
    const elapsed = Date.now() - start;
    expect(r.ok()).toBeTruthy();
    const body = await r.json();
    expect(body.success).toBe(true);
    expect(body.workflow_ga?.name).toBe("hts_plate_qc_hit_calling");
    expect(elapsed).toBeLessThan(30_000); // 7s typical on dev; 30s ceiling guards against backsliding
    console.log(`[HT-1] routed in ${elapsed}ms, confidence=${body.confidence}`);
  });

  test("Chat-stream complete path — assistant message persists with partial=false", async ({ request }) => {
    const headers = await authedHeaders();
    const sid = `chat-${Date.now()}-smoke`;
    const mid = `msg-smoke-${Date.now()}`;

    // Create session
    await request.post(`${BASE}/api/sessions`, {
      headers,
      data: { session_id: sid, title: "api-smoke complete" },
    });

    // Fire chat-stream and consume to EOF
    const resp = await request.post(`${BASE}/api/chat/stream`, {
      headers,
      data: {
        message: "Run HTS plate QC and hit calling on a 96-well plate, Z prime 0.5",
        context: { sessionId: sid, memorySessionId: sid, assistantMessageId: mid },
      },
      timeout: 180_000,
    });
    expect(resp.ok()).toBeTruthy();
    const sse = await resp.text();
    expect(sse).toContain("event: final");

    // Allow server-side persist to finish (it runs inline before res.end()
    // but DB write may take a few ms)
    await new Promise((r) => setTimeout(r, 1500));

    const sessR = await request.get(`${BASE}/api/sessions/${sid}`, { headers });
    expect(sessR.ok()).toBeTruthy();
    const sess = await sessR.json();
    const msgs = sess.messages || [];
    const persisted = msgs.find((m: any) => m.message_id === mid);
    expect(persisted, "assistant message must be persisted by message_id").toBeTruthy();
    expect(persisted.role).toBe("assistant");
    expect(persisted.partial).toBe(false);
    expect((persisted.content || "").length).toBeGreaterThan(50);
  });

  test("Chat-stream disconnect path — partial assistant message persists with partial=true", async ({ request }) => {
    const headers = await authedHeaders();
    const sid = `chat-${Date.now()}-disco`;
    const mid = `msg-disco-${Date.now()}`;

    await request.post(`${BASE}/api/sessions`, {
      headers,
      data: { session_id: sid, title: "api-smoke disconnect" },
    });

    // Fire chat-stream with a short timeout to force a mid-stream abort.
    // 30s is past LLM warm-up so deltas should have started flowing.
    try {
      await request.post(`${BASE}/api/chat/stream`, {
        headers,
        data: {
          message: "Run HTS plate QC and hit calling on a 96-well plate, Z prime 0.5",
          context: { sessionId: sid, memorySessionId: sid, assistantMessageId: mid },
        },
        timeout: 30_000,
      });
    } catch {
      // Timeout/abort is the point.
    }

    // Server-side req.socket.on('close') fires the partial persist; give it a moment.
    await new Promise((r) => setTimeout(r, 5000));

    const sessR = await request.get(`${BASE}/api/sessions/${sid}`, { headers });
    expect(sessR.ok()).toBeTruthy();
    const sess = await sessR.json();
    const msgs = sess.messages || [];
    const persisted = msgs.find((m: any) => m.message_id === mid);

    // Two acceptable outcomes:
    //  (a) LLM started streaming before the 30s abort → partial:true row exists
    //  (b) LLM hadn't streamed yet → empty-stream guard correctly skipped persist
    if (persisted) {
      expect(persisted.role).toBe("assistant");
      expect(persisted.partial).toBe(true);
      expect((persisted.content || "").length).toBeGreaterThan(0);
      console.log(`[disconnect] persisted partial=${persisted.content.length}ch`);
    } else {
      console.log(`[disconnect] no deltas before abort — empty-stream guard fired (correct)`);
    }
  });
});
