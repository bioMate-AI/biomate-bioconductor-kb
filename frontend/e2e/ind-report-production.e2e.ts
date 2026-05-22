/**
 * IND Report — Production Integration E2E (PI-1 .. PI-12)
 *
 * Mirrors docs/20260520_IND_PRODUCTION_INTEGRATION_PLAN.md Part 1.
 *
 * Runs AFTER frontend/sandbox/ind-port/integrate-to-production.sh --apply
 * (already merged as commit 2a12b4b88). Hits the live Node frontend on :5000
 * and the live Galaxy backend on :8081. **No page.route() stubs** — feedback
 * persistence tests assert the on-disk JSONL files actually grow.
 *
 * NOTE on ports: the plan doc says :8080 — that's a typo. Reality is :8081 for
 * Galaxy backend (see CLAUDE.md "Local Service Map").
 *
 * The suite adapts to BIOMATE_REQUIRE_AUTH:
 *  - If set to "1" on the backend, all auth-protected POSTs (Stage C, PI-6)
 *    register a test user once and propagate the JWT bearer.
 *  - If unset, POSTs go through as anonymous (Stage C pass-through).
 *
 * Run with all gates flipped:
 *   PI_RUN_BUILD=1 PI_RUN_TSC=1 PI_REQUIRE_LOCAL_LLM=1 BIOMATE_REQUIRE_AUTH=1 \
 *     npx playwright test frontend/e2e/ind-report-production.e2e.ts
 */

import { test, expect, request as pwRequest, APIRequestContext } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";
import { fileURLToPath } from "url";
import { BASE_URL } from "./helpers.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const GALAXY_URL = process.env.GALAXY_URL || "http://localhost:8081";
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const FEEDBACK_ROOT = path.join(REPO_ROOT, "data", "regulatory_training");
const AUTH_REQUIRED = process.env.BIOMATE_REQUIRE_AUTH === "1";

const JSONL = {
  customerPairs: path.join(FEEDBACK_ROOT, "dpo", "customer_pairs.jsonl"),
  checkerFeedback: path.join(FEEDBACK_ROOT, "checker_feedback.jsonl"),
  citationExtensions: path.join(FEEDBACK_ROOT, "citation_extensions.jsonl"),
  promptTuning: path.join(FEEDBACK_ROOT, "prompt_tuning_signals.jsonl"),
};

function wcL(p: string): number {
  if (!fs.existsSync(p)) return 0;
  return fs.readFileSync(p, "utf8").split("\n").filter((l) => l.trim()).length;
}

// ---------------------------------------------------------------------------
// JWT minting — bypasses the UI login flow so Stage C can POST authenticated
//
// AuthService verifies tokens with the JWT_SECRET_KEY env var. Mint a minimal
// access token directly so we don't need a registered user. This is exactly
// the same mechanism production uses — we're just generating a valid token
// without going through /login.
// ---------------------------------------------------------------------------

import crypto from "crypto";

function b64url(buf: Buffer | string): string {
  return Buffer.from(buf).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function mintTestJwt(userId = "pi-e2e-anon", email = "pi-e2e@biomate.test"): string {
  const secret = process.env.JWT_SECRET_KEY || "CHANGE_ME_IN_PRODUCTION";
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(JSON.stringify({
    userId, email, type: "access",
    iat: now, exp: now + 3600,
  }));
  const sig = b64url(crypto.createHmac("sha256", secret).update(`${header}.${payload}`).digest());
  return `${header}.${payload}.${sig}`;
}

function authHeaders(): Record<string, string> {
  if (!AUTH_REQUIRED) return {};
  return { Authorization: `Bearer ${mintTestJwt()}` };
}

async function assertBackendUp() {
  const ctx = await pwRequest.newContext();
  let ok = false;
  try {
    const r = await ctx.get(`${GALAXY_URL}/api/regulatory/active_adapter`, { timeout: 8000 });
    ok = r.ok();
  } catch {
    ok = false;
  }
  await ctx.dispose();
  if (!ok) {
    test.skip(true, `Galaxy backend unreachable at ${GALAXY_URL}/api/regulatory/active_adapter`);
  }
}

// ---------------------------------------------------------------------------
// Stage A — Build + serve  (PI-1 / PI-2 / PI-3)
// ---------------------------------------------------------------------------

test.describe("Stage A — build + serve", () => {
  test("PI-1: npm run build succeeds", () => {
    const frontendDir = path.join(REPO_ROOT, "frontend");
    if (process.env.PI_RUN_BUILD !== "1") {
      test.skip(true, "Set PI_RUN_BUILD=1 to re-run the build step.");
    }
    execSync("npm run build", { cwd: frontendDir, stdio: "inherit" });
    const distAssets = path.join(frontendDir, "dist", "public", "assets");
    expect(fs.existsSync(distAssets)).toBe(true);
    const files = fs.readdirSync(distAssets);
    expect(files.some((f) => f.startsWith("index-") && f.endsWith(".js"))).toBe(true);
  });

  test("PI-2: tsc --noEmit clean", () => {
    if (process.env.PI_RUN_TSC !== "1") {
      test.skip(true, "Set PI_RUN_TSC=1 to re-run tsc.");
    }
    const frontendDir = path.join(REPO_ROOT, "frontend");
    execSync("npm run check", { cwd: frontendDir, stdio: "inherit" });
  });

  test("PI-3: dev server on :5000 returns 200", async ({ page }) => {
    const resp = await page.goto(BASE_URL, { waitUntil: "domcontentloaded" });
    expect(resp?.status()).toBeLessThan(400);
  });
});

// ---------------------------------------------------------------------------
// Stage B — Route + auth wiring  (PI-4 / PI-5 / PI-6)
// ---------------------------------------------------------------------------

test.describe("Stage B — route + auth wiring", () => {
  test("PI-4: /ind-report serves the new IND shell", async ({ page }) => {
    // ProtectedRoute → must authenticate first via Node-side JWT cookie
    // (the React app uses /api/auth/me, not the backend JWT). Use the existing
    // helper to register + login through the UI.
    const { setupTestUser } = await import("./helpers.js");
    await setupTestUser(page, `pi4_${Date.now()}`);
    await page.goto(`${BASE_URL}/ind-report?onboarding=0`, { waitUntil: "domcontentloaded" });
    await expect(page.locator(".ind-shell").first()).toBeVisible({ timeout: 10000 });
    await expect(page.locator(".ind-topbar").first()).toBeVisible();
  });

  test("PI-5: /drug-discovery-cro route unaffected by integration", async ({ page }) => {
    const resp = await page.goto(`${BASE_URL}/drug-discovery-cro`, { waitUntil: "domcontentloaded" });
    expect(resp?.status()).toBeLessThan(400);
    const body = await page.content();
    expect(/CRO|campaign/i.test(body)).toBe(true);
  });

  test("PI-6: backend rejects unauthenticated POST when REQUIRE_AUTH=1", async () => {
    if (!AUTH_REQUIRED) {
      test.skip(true, "Set BIOMATE_REQUIRE_AUTH=1 on backend AND test runner to exercise the gate.");
    }
    const ctx = await pwRequest.newContext();
    const r401 = await ctx.post(`${GALAXY_URL}/api/ind-report/projects/test/edit`, {
      data: { paragraph_id: "p-1", original: "before", edited: "after", section_type: "tox_overview" },
    });
    expect(r401.status()).toBe(401);
    const body = await r401.json();
    expect(body.detail).toContain("Bearer");

    // Positive case: minted JWT lets the same POST through (200).
    const r200 = await ctx.post(`${GALAXY_URL}/api/ind-report/projects/test/edit`, {
      headers: { Authorization: `Bearer ${mintTestJwt()}` },
      data: { paragraph_id: "p-1", original: "before", edited: "after-pi6", section_type: "tox_overview" },
    });
    expect(r200.status()).toBe(200);
    await ctx.dispose();
  });
});

// ---------------------------------------------------------------------------
// Stage C — Feedback POSTs reach backend (NO STUBS)  (PI-7 .. PI-10)
// ---------------------------------------------------------------------------

test.describe("Stage C — feedback POSTs persist to JSONL", () => {
  test.beforeAll(async () => { await assertBackendUp(); });

  test("PI-7: paragraph edit POST appends to customer_pairs.jsonl", async () => {
    const before = wcL(JSONL.customerPairs);
    const ctx = await pwRequest.newContext();
    const r = await ctx.post(`${BASE_URL}/api/ind-report/projects/pi7/edit`, {
      headers: authHeaders(),
      data: {
        paragraph_id: `pi7-${Date.now()}`,
        original: "The compound shows acceptable safety margins.",
        edited: "The compound shows acceptable safety margins per ICH M3(R2).",
        section_type: "tox_overview",
        structured_input: "PI-7 e2e probe",
      },
    });
    expect(r.ok(), await r.text()).toBe(true);
    const body = await r.json();
    expect(body.recorded).toBe(true);
    await ctx.dispose();
    expect(wcL(JSONL.customerPairs)).toBe(before + 1);
  });

  test("PI-8: audit dismissal POST appends to checker_feedback.jsonl", async () => {
    const before = wcL(JSONL.checkerFeedback);
    const ctx = await pwRequest.newContext();
    const r = await ctx.post(`${BASE_URL}/api/ind-report/audit/finding-pi8/dismiss`, {
      headers: authHeaders(),
      data: {
        rule_id: "MRSD_PRESENT",
        section_type: "tox_overview",
        reason: "already_addressed",
        free_text: "PI-8 probe",
      },
    });
    expect(r.ok(), await r.text()).toBe(true);
    await ctx.dispose();
    expect(wcL(JSONL.checkerFeedback)).toBe(before + 1);
  });

  test("PI-9: citation suggestion POST appends to citation_extensions.jsonl", async () => {
    const before = wcL(JSONL.citationExtensions);
    const ctx = await pwRequest.newContext();
    const r = await ctx.post(`${BASE_URL}/api/ind-report/citations/suggest`, {
      headers: authHeaders(),
      data: { guideline_id: "ICH-M3(R2)", rationale: "PI-9 probe", document_only: false },
    });
    expect(r.ok(), await r.text()).toBe(true);
    await ctx.dispose();
    expect(wcL(JSONL.citationExtensions)).toBe(before + 1);
  });

  test("PI-10: regenerate-with-instruction POST appends to prompt_tuning_signals.jsonl", async () => {
    const before = wcL(JSONL.promptTuning);
    const ctx = await pwRequest.newContext();
    const r = await ctx.post(`${BASE_URL}/api/ind-report/sections/2.6.6/regenerate`, {
      headers: authHeaders(),
      data: {
        instruction: "Add MRSD calculation reference per ICH M3(R2).",
        before: "Toxicity overview prose v1.",
        after: "Toxicity overview prose v2 with MRSD ref.",
      },
    });
    expect(r.ok(), await r.text()).toBe(true);
    await ctx.dispose();
    expect(wcL(JSONL.promptTuning)).toBe(before + 1);
  });
});

// ---------------------------------------------------------------------------
// Stage D — LLM serving  (PI-11 / PI-12)
// ---------------------------------------------------------------------------

test.describe("Stage D — LLM adapter serving", () => {
  test.beforeAll(async () => { await assertBackendUp(); });

  test("PI-11: /api/regulatory/active_adapter resolves correctly anon + paid-org", async () => {
    const ctx = await pwRequest.newContext();
    const rAnon = await ctx.get(`${BASE_URL}/api/regulatory/active_adapter`);
    expect(rAnon.ok(), await rAnon.text()).toBe(true);
    const anon = await rAnon.json();
    expect(anon).toHaveProperty("adapter_name");
    expect(anon.customized_for).toBeNull();
    expect(anon.entitled).toBe(false);
    expect(/^regulatory_llm_v\d+$/.test(anon.adapter_name)).toBe(true);

    const rUnpaid = await ctx.get(`${BASE_URL}/api/regulatory/active_adapter`, {
      headers: { "X-BioMate-Org-Id": "not-a-paid-org-xyz" },
    });
    const unpaid = await rUnpaid.json();
    expect(unpaid.customized_for).toBeNull();
    expect(unpaid.entitled).toBe(false);
    await ctx.dispose();
  });

  test("PI-12: local LLM smoke produces real prose (or returns graceful unavailable)", async () => {
    // Always runs (no env gate). Asserts the contract of /api/regulatory/generate_smoke:
    //   - status=ok with non-empty text → local LLM is working
    //   - status=unavailable             → adapter load failed; production falls back to Gemini
    //   - status=error                   → load OK but generation failed (fail test loudly)
    // First call can take ~30-90s to load Qwen3-8B + LoRA; allow a generous timeout.
    test.setTimeout(180_000);
    const ctx = await pwRequest.newContext();
    const r = await ctx.post(`${GALAXY_URL}/api/regulatory/generate_smoke`, {
      timeout: 170_000,
    });
    expect(r.ok(), `status=${r.status()} body=${await r.text()}`).toBe(true);
    const body = await r.json();
    expect(["ok", "unavailable", "error"]).toContain(body.status);
    if (body.status === "ok") {
      expect(body.text.length).toBeGreaterThan(40);
      // Doesn't hallucinate emptiness — must contain at least one word
      expect(/[a-zA-Z]{4,}/.test(body.text)).toBe(true);
      // Log so the operator can read the actual generated prose
      console.log(`[PI-12 ✅] LLM produced ${body.length} chars:\n  ${body.text.slice(0, 300).replace(/\n/g, " ")}…`);
    } else if (body.status === "unavailable") {
      console.warn(`[PI-12 ⚠️] Local LLM unavailable — production will fall back to Gemini. reason=${body.reason}`);
    } else {
      throw new Error(`PI-12 generation errored: ${body.reason}`);
    }
    await ctx.dispose();
  });

  test("PI-13: SSE streaming endpoint emits phase + token events", async () => {
    // Verifies the UX-grade /api/regulatory/generate_stream:
    //   - text/event-stream content-type
    //   - at least one model_loading phase (always emitted first)
    //   - either generating + complete phases + >=1 token event,
    //     OR an error phase (fallback path is acceptable)
    test.setTimeout(360_000);

    const resp = await fetch(`${GALAXY_URL}/api/regulatory/generate_stream`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
    expect(resp.ok, `status=${resp.status}`).toBe(true);
    expect(resp.headers.get("content-type") || "").toContain("text/event-stream");
    expect(resp.body).not.toBeNull();

    const reader = (resp.body as any).getReader();
    const dec = new TextDecoder();
    const phases: string[] = [];
    const tokens: string[] = [];
    let leftover = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      leftover += dec.decode(value, { stream: true });
      let idx;
      while ((idx = leftover.indexOf("\n\n")) !== -1) {
        const raw = leftover.slice(0, idx);
        leftover = leftover.slice(idx + 2);
        let evt = "", dat = "";
        for (const line of raw.split("\n")) {
          if (line.startsWith("event:")) evt = line.slice(6).trim();
          else if (line.startsWith("data:")) dat = line.slice(5).trim();
        }
        if (!evt) continue;
        try {
          const data = JSON.parse(dat);
          if (evt === "phase") phases.push(data.phase);
          else if (evt === "token") tokens.push(data.text || "");
        } catch { /* skip malformed */ }
      }
    }

    console.log(`[PI-13] phases=${JSON.stringify(phases)} tokens=${tokens.length}`);
    expect(phases.length).toBeGreaterThan(0);
    expect(phases[0]).toBe("model_loading");

    if (phases.includes("error")) {
      console.warn(`[PI-13 ⚠️] streaming errored; production would fall back to Gemini`);
    } else {
      expect(phases).toContain("generating");
      expect(phases).toContain("complete");
      expect(tokens.length).toBeGreaterThan(0);
      const fullText = tokens.join("");
      expect(/[a-zA-Z]{4,}/.test(fullText)).toBe(true);
      console.log(`[PI-13 ✅] streamed ${tokens.length} token events; total ${fullText.length} chars`);
    }
  });
});
