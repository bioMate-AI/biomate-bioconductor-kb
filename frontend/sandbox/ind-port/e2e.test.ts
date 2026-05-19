/**
 * IND Report — merged E2E test suite (Phase 1).
 *
 * Mirrors frontend/e2e/cryoem-stepwise-and-output.e2e.ts:
 *   - Per-test SuiteRecord → .test-output/ind-suite-audit.json
 *   - One super-merged "happy path" test that walks the full pipeline
 *   - Screenshots organized by test ID under .snapshots/e2e/
 *   - No assertion fires silently — every expect() also appends to audit
 *
 * Plan: docs/20260519_IND_E2E_TEST_PLAN.md
 *
 * Phase 1 (this file): IND-1 … IND-14 + IND-HAPPY
 * Phase 2-4 (deferred): feedback-API live-backend coverage, sign overlay
 *   TOTP validation, responsive smoke, super-merged with real adapter.
 */
import { test, expect, type Page, type Route } from "@playwright/test";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SS_DIR = path.join(__dirname, ".snapshots", "e2e");
const OUT_DIR = path.join(__dirname, ".test-output");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Audit shape — every test produces one of these
// ---------------------------------------------------------------------------

interface FeedbackEvent {
  surface: "edit" | "dismiss" | "cite" | "regenerate";
  paragraph_id?: string;
  finding_id?: string;
  request_payload: Record<string, unknown>;
  response_status: number;
  posted: boolean;
}

interface AuditCounts {
  critical: number;
  major: number;
  minor: number;
  info: number;
}

interface IndSuiteRecord {
  testId: string;
  projectId: string | null;
  startTs: number;
  endTs: number;
  finalStatus: "passed" | "failed" | "skipped";
  wallTimeMs: number;
  feedbackEvents: FeedbackEvent[];
  stepStates: Record<string, string | null>;
  auditCountsStart: AuditCounts | null;
  auditCountsEnd: AuditCounts | null;
  regionAt: string[];
  visualDiffPct: number | null;
  assertions: { name: string; passed: boolean; note?: string }[];
  screenshots: string[];
  error?: string;
}

const SUITE_AUDIT: IndSuiteRecord[] = [];

function newAudit(testId: string): IndSuiteRecord {
  return {
    testId, projectId: null,
    startTs: Date.now(), endTs: 0,
    finalStatus: "skipped", wallTimeMs: 0,
    feedbackEvents: [],
    stepStates: { s1: null, s2: null, s3: null, s4: null, s5: null },
    auditCountsStart: null, auditCountsEnd: null,
    regionAt: [], visualDiffPct: null,
    assertions: [], screenshots: [],
  };
}

function finalize(audit: IndSuiteRecord, status: "passed" | "failed", err?: Error) {
  audit.endTs = Date.now();
  audit.wallTimeMs = audit.endTs - audit.startTs;
  audit.finalStatus = status;
  if (err) audit.error = err.message;
  SUITE_AUDIT.push(audit);
}

// Async-aware recording wrapper around expect() — MUST be awaited at every
// call site so async `check` functions resolve before the test ends.
async function asserts(
  audit: IndSuiteRecord, name: string,
  check: () => unknown, note?: string,
) {
  try {
    await check();
    audit.assertions.push({ name, passed: true, note });
  } catch (err) {
    audit.assertions.push({ name, passed: false, note: (err as Error).message });
    throw err;
  }
}

async function shot(page: Page, testId: string, name: string, audit: IndSuiteRecord) {
  const file = `${testId}-${name}.png`;
  const out = path.join(SS_DIR, file);
  await page.screenshot({ path: out });
  audit.screenshots.push(file);
}

// ---------------------------------------------------------------------------
// captureFeedback — install route handlers that record every Appendix-B POST
// ---------------------------------------------------------------------------

async function captureFeedback(page: Page, audit: IndSuiteRecord, opts?: { stub?: boolean }) {
  const stub = opts?.stub ?? true;
  const routes: { surface: FeedbackEvent["surface"]; pattern: RegExp }[] = [
    { surface: "edit",       pattern: /\/api\/ind-report\/projects\/.+\/edit$/ },
    { surface: "dismiss",    pattern: /\/api\/ind-report\/audit\/.+\/dismiss$/ },
    { surface: "cite",       pattern: /\/api\/ind-report\/citations\/suggest$/ },
    { surface: "regenerate", pattern: /\/api\/ind-report\/sections\/.+\/regenerate$/ },
  ];
  for (const { surface, pattern } of routes) {
    await page.route(pattern, async (route: Route) => {
      const payload = route.request().postDataJSON() as Record<string, unknown>;
      audit.feedbackEvents.push({
        surface,
        paragraph_id: payload.paragraph_id as string | undefined,
        request_payload: payload,
        response_status: 200,
        posted: true,
      });
      if (stub) {
        await route.fulfill({
          status: 200, contentType: "application/json",
          body: JSON.stringify({ recorded: true, id: `stub-${audit.feedbackEvents.length}` }),
        });
      } else {
        await route.continue();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// DOM observers — step state, audit counts, region selector
// ---------------------------------------------------------------------------

async function readStepStates(page: Page): Promise<Record<string, string | null>> {
  return await page.evaluate(() => {
    const out: Record<string, string | null> = { s1: null, s2: null, s3: null, s4: null, s5: null };
    Array.from(document.querySelectorAll(".ind-step")).forEach((el, i) => {
      const cls = (el as HTMLElement).className;
      out[`s${i + 1}`] =
        cls.includes("running") ? "running" :
        cls.includes("blocked") ? "blocked" :
        cls.includes("failed")  ? "failed"  :
        cls.includes("complete") ? "complete" : "pending";
    });
    return out;
  });
}

async function readAuditCounts(page: Page): Promise<AuditCounts | null> {
  return await page.evaluate(() => {
    const root = document.querySelector('[data-tour="ind-audit-summary"]');
    if (!root) return null;
    const text = root.textContent ?? "";
    const m = (k: string) => {
      const re = new RegExp(`(\\d+)\\s+${k}`);
      const match = text.match(re);
      return match ? parseInt(match[1], 10) : 0;
    };
    return { critical: m("CRITICAL"), major: m("MAJOR"), minor: m("MINOR"), info: m("INFO") };
  });
}

async function readRegion(page: Page): Promise<string | null> {
  return await page.locator(".ind-doc-region select").inputValue().catch(() => null);
}

// ---------------------------------------------------------------------------
// afterAll — write the audit JSON
// ---------------------------------------------------------------------------

test.afterAll(async () => {
  const summary = {
    suiteId: "ind-report-e2e",
    generatedAt: new Date().toISOString(),
    passed: SUITE_AUDIT.filter((r) => r.finalStatus === "passed").length,
    failed: SUITE_AUDIT.filter((r) => r.finalStatus === "failed").length,
    total: SUITE_AUDIT.length,
    runs: SUITE_AUDIT,
  };
  const out = path.join(OUT_DIR, "ind-suite-audit.json");
  fs.writeFileSync(out, JSON.stringify(summary, null, 2));
  console.log(`[ind-audit] ${summary.passed}/${summary.total} → ${out}`);
});

// ===========================================================================
// Section A — Visual / structural landmarks (IND-1 … IND-6)
// ===========================================================================

test("IND-1: Onboarding EmptyState renders 3 reference compound chips, Start exits", async ({ page }) => {
  const audit = newAudit("IND-1");
  try {
    await page.goto("/?onboarding=1");
    await page.waitForSelector(".ind-empty");
    await shot(page, "IND-1", "01_empty_state", audit);
    await asserts(audit, "title shows BioMate IND Report",
      async () => expect(await page.locator(".ind-empty-card h1").textContent()).toContain("BioMate IND Report"));
    await asserts(audit, "exactly 3 reference compound chips",
      async () => await expect(page.locator(".ind-ref-chip")).toHaveCount(3));
    await asserts(audit, "Start button advances out of onboarding", async () => {
      await page.locator(".ind-empty-start").click();
      await expect(page.locator(".ind-shell .ind-center")).toBeVisible();
    });
    await shot(page, "IND-1", "02_post_start", audit);
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-2: Topbar — breadcrumb + region chips + tutorial + user avatar", async ({ page }) => {
  const audit = newAudit("IND-2");
  audit.projectId = "p-bm0042";
  try {
    await page.goto("/");
    await page.waitForSelector(".ind-topbar");
    await shot(page, "IND-2", "01_topbar", audit);
    await asserts(audit, "breadcrumb shows IND Report",
      async () => await expect(page.locator(".ind-topbar .ind-crumb")).toContainText("IND Report"));
    await asserts(audit, "breadcrumb shows BM-0042 in bold",
      async () => await expect(page.locator(".ind-topbar .ind-crumb b")).toContainText("BM-0042"));
    await asserts(audit, "4 region chips",
      async () => await expect(page.locator(".ind-topbar .r-chip")).toHaveCount(4));
    await asserts(audit, "tutorial button visible",
      async () => await expect(page.locator(".ind-topbar .tut-btn")).toContainText("Tutorial"));
    await asserts(audit, "user avatar JS visible",
      async () => await expect(page.locator(".ind-topbar .user-avatar")).toContainText("JS"));
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-3: LeftNav — project list with status dots, active highlight, footer", async ({ page }) => {
  const audit = newAudit("IND-3");
  try {
    await page.goto("/");
    await page.waitForSelector(".ind-left");
    await shot(page, "IND-3", "01_leftnav", audit);
    await asserts(audit, "3 demo projects",
      async () => await expect(page.locator(".ind-projects .ind-project")).toHaveCount(3));
    await asserts(audit, "active project has .active class",
      async () => await expect(page.locator(".ind-project.active")).toHaveCount(1));
    await asserts(audit, "signed/in_progress/blocked dots all present", async () => {
      await expect(page.locator(".ind-project-dot.signed")).toHaveCount(1);
      await expect(page.locator(".ind-project-dot.in_progress")).toHaveCount(1);
      await expect(page.locator(".ind-project-dot.blocked")).toHaveCount(1);
    });
    await asserts(audit, "switching project swaps active class", async () => {
      await page.locator(".ind-projects .ind-project").nth(1).click();
      await expect(page.locator(".ind-projects .ind-project").nth(1)).toHaveClass(/active/);
    });
    await shot(page, "IND-3", "02_after_switch", audit);
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-4: Pipeline structure — 5 step cards, all complete in demo state", async ({ page }) => {
  const audit = newAudit("IND-4");
  try {
    await page.goto("/");
    await page.waitForSelector(".ind-shell");
    audit.stepStates = await readStepStates(page);
    await asserts(audit, "exactly 5 step cards",
      async () => await expect(page.locator("main.ind-center .ind-step")).toHaveCount(5));
    await asserts(audit, "all 5 steps complete in demo state", () => {
      for (const s of ["s1", "s2", "s3", "s4", "s5"]) {
        expect(audit.stepStates[s]).toBe("complete");
      }
    });
    await shot(page, "IND-4", "01_pipeline", audit);
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-5: DocPanel — version chip + region selector + 6 section tabs + SHA footer", async ({ page }) => {
  const audit = newAudit("IND-5");
  try {
    await page.goto("/");
    await page.waitForSelector(".ind-doc-panel");
    await shot(page, "IND-5", "01_doc_panel", audit);
    await asserts(audit, "title shows Module 2.6",
      async () => await expect(page.locator(".ind-doc-title")).toContainText("Module 2.6"));
    await asserts(audit, "version chip renders v2",
      async () => await expect(page.locator(".ver-chip")).toContainText(/v\d/));
    await asserts(audit, "6 section tabs",
      async () => await expect(page.locator(".ind-doc-tab")).toHaveCount(6));
    const region = await readRegion(page);
    audit.regionAt.push(region ?? "?");
    await asserts(audit, "region selector defaults to FDA", () => expect(region).toBe("FDA"));
    await asserts(audit, "footer SHA-256 visible",
      async () => await expect(page.locator(".ind-doc-foot")).toContainText("SHA-256"));
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-6: OKLCH region chips have distinct non-default backgrounds", async ({ page }) => {
  const audit = newAudit("IND-6");
  try {
    await page.goto("/");
    const colors = await page.evaluate(() => {
      const out: Record<string, string> = {};
      for (const r of ["fda", "ema", "nmpa", "pmda"]) {
        const el = document.querySelector(`.r-chip.${r}`);
        if (el) out[r] = getComputedStyle(el as HTMLElement).backgroundColor;
      }
      return out;
    });
    await asserts(audit, "4 distinct chip colors", () => {
      expect(new Set(Object.values(colors)).size).toBe(4);
    }, JSON.stringify(colors));
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

// ===========================================================================
// Section B — Step cards (IND-7 … IND-14)
// ===========================================================================

test("IND-7: Step 1 Project Setup — kv list + region toggles + lead SMILES", async ({ page }) => {
  const audit = newAudit("IND-7");
  try {
    await page.goto("/");
    const step1 = page.locator(".ind-step").nth(0);
    await step1.locator(".ind-step-head").click();
    await page.waitForTimeout(200);
    await shot(page, "IND-7", "01_step1_expanded", audit);
    await asserts(audit, "kv list rendered with Molecule key",
      async () => await expect(step1.locator(".kv-list .k").first()).toContainText("Molecule"));
    await asserts(audit, "region toggles row visible",
      async () => await expect(step1.locator(".ind-region-row")).toBeVisible());
    await asserts(audit, "lead SMILES (mono font) visible",
      async () => await expect(step1.locator(".v.mono")).toBeVisible());
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-8: Step 2 ADMET complete — gates row + expandable table + wet-lab panel", async ({ page }) => {
  const audit = newAudit("IND-8");
  try {
    await page.goto("/");
    const step2 = page.locator(".ind-step").nth(1);
    await step2.locator(".ind-step-head").click();
    await page.waitForTimeout(200);
    await asserts(audit, "status text shows N/M pass",
      async () => await expect(step2.locator(".ind-step-status")).toContainText(/\d+\/\d+ pass/));
    await asserts(audit, "View ADMET table link toggles table", async () => {
      const link = step2.locator("button.ind-link", { hasText: /ADMET table/ }).first();
      await link.click();
      await expect(step2.locator("table.ind-table")).toBeVisible();
    });
    await shot(page, "IND-8", "01_table_open", audit);
    await asserts(audit, "Add wet-lab data link opens upload panel", async () => {
      const wetlab = step2.locator("button.ind-link", { hasText: /wet-lab/ });
      await wetlab.click();
      await expect(step2.locator(".ind-wetlab")).toBeVisible();
    });
    await shot(page, "IND-8", "02_wetlab_open", audit);
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test.skip("IND-9: Step 2 ADMET running state (needs ?state=running knob in page)", async () => {});
test.skip("IND-10: Step 2 imported-from-chat banner (needs ?imported=1 knob)", async () => {});

test("IND-11: Step 3 PBPK passed — EMA criterion green + EMA/FDA two-chip status", async ({ page }) => {
  const audit = newAudit("IND-11");
  try {
    await page.goto("/");
    const step3 = page.locator(".ind-step").nth(2);
    await step3.locator(".ind-step-head").click();
    await page.waitForTimeout(200);
    await shot(page, "IND-11", "01_pbpk_passed", audit);
    await asserts(audit, "status row has EMA ✓ chip",
      async () => await expect(step3.locator(".ind-step-status .r-chip.ema")).toBeVisible());
    await asserts(audit, "status row has FDA ✓ chip",
      async () => await expect(step3.locator(".ind-step-status .r-chip.fda")).toBeVisible());
    await asserts(audit, "criterion box says EMA criterion met",
      async () => await expect(step3).toContainText("EMA criterion met"));
    await asserts(audit, "Cmax and AUC within-2-fold shown", async () => {
      await expect(step3).toContainText("Cmax:");
      await expect(step3).toContainText("AUC:");
    });
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test.skip("IND-12: Step 3 PBPK failed (needs ?state=pbpk-fail knob)", async () => {});

test("IND-13: Step 4 Lead Selection — top-5 table + OOD chip + AD count", async ({ page }) => {
  const audit = newAudit("IND-13");
  try {
    await page.goto("/");
    const step4 = page.locator(".ind-step").nth(3);
    await step4.locator(".ind-step-head").click();
    await page.waitForTimeout(200);
    await shot(page, "IND-13", "01_leads_table", audit);
    await asserts(audit, "ranking table has 5 rows",
      async () => await expect(step4.locator('[data-tour="ind-leads-table"] tbody tr')).toHaveCount(5));
    await asserts(audit, "row 1 has .lead class",
      async () => await expect(step4.locator('[data-tour="ind-leads-table"] tbody tr').nth(0)).toHaveClass(/lead/));
    await asserts(audit, "applicability domain count visible",
      async () => await expect(step4).toContainText(/\d+\/\d+ in-domain/));
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

test("IND-14: Step 5 IND Document — audit chips + regions + completeness + Sign button", async ({ page }) => {
  const audit = newAudit("IND-14");
  try {
    await page.goto("/");
    const step5 = page.locator(".ind-step").nth(4);
    await shot(page, "IND-14", "01_step5", audit);
    audit.auditCountsEnd = await readAuditCounts(page);
    await asserts(audit, "audit summary row exists",
      async () => await expect(step5.locator('[data-tour="ind-audit-summary"]')).toBeVisible());
    await asserts(audit, "audit counts parsed and MAJOR > 0", () => {
      expect(audit.auditCountsEnd?.major ?? 0).toBeGreaterThan(0);
    });
    await asserts(audit, "coverage list has rows",
      async () => {
        const count = await step5.locator(".coverage-list .coverage-row").count();
        expect(count).toBeGreaterThan(0);
      });
    await asserts(audit, "MAJOR-warn row visible when major > 0", async () => {
      if ((audit.auditCountsEnd?.major ?? 0) > 0) {
        await expect(step5.locator(".ind-major-warn")).toBeVisible();
      }
    });
    await asserts(audit, "Sign action button present (warn or primary)",
      async () => await expect(
        step5.locator(".ind-step-actions .ind-btn.warn, .ind-step-actions .ind-btn.primary")
      ).toBeVisible());
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});

// ===========================================================================
// IND-HAPPY — super-merged happy path
// ===========================================================================

test("IND-HAPPY: full pipeline (onboarding → audit dismiss → edit → cite → regenerate → sign)", async ({ page }) => {
  test.setTimeout(120_000);
  const audit = newAudit("IND-HAPPY");
  audit.projectId = "p-bm0042";
  await captureFeedback(page, audit, { stub: true });

  try {
    // ── Stage 1: onboarding ────────────────────────────────────────────
    await page.goto("/?onboarding=1");
    await page.waitForSelector(".ind-empty");
    await shot(page, "IND-HAPPY", "01_onboarding", audit);
    await asserts(audit, "stage1: onboarding renders 3 ref compounds",
      async () => await expect(page.locator(".ind-ref-chip")).toHaveCount(3));

    // ── Stage 2: enter main view via "Start with a compound" ────────────
    await page.locator(".ind-empty-start").click();
    await page.waitForSelector(".ind-shell .ind-center");
    audit.stepStates = await readStepStates(page);
    audit.auditCountsStart = await readAuditCounts(page);
    audit.regionAt.push((await readRegion(page)) ?? "?");
    await shot(page, "IND-HAPPY", "02_main", audit);
    await asserts(audit, "stage2: shell + doc panel mounted", async () => {
      await expect(page.locator(".ind-shell main.ind-center")).toBeVisible();
      await expect(page.locator(".ind-doc-panel")).toBeVisible();
    });

    // ── Stage 3: open Audit overlay from center-head ────────────────────
    await page.locator(".ind-center-head button.ind-btn.sm").first().click();
    await expect(page.locator(".ind-audit-overlay")).toBeVisible();
    await shot(page, "IND-HAPPY", "03_audit_overlay", audit);
    await asserts(audit, "stage3: audit overlay visible",
      async () => await expect(page.locator(".ind-audit-overlay h3")).toContainText("Regulatory Audit"));

    // ── Stage 4: dismiss a finding → captureDismissal POST ─────────────
    await page.locator(".ind-audit-finding button.ind-link", { hasText: "Dismiss" }).first().click();
    await page.locator(".ind-dismiss-picker input[type=radio]").first().check();
    await page.locator(".ind-dismiss-picker button.primary").click();
    await page.waitForTimeout(400);
    await asserts(audit, "stage4: dismiss POST fired with reason=not_applicable", () => {
      const event = audit.feedbackEvents.find((e) => e.surface === "dismiss");
      expect(event).toBeTruthy();
      expect(event?.request_payload.reason).toBe("not_applicable");
    });

    // ── Stage 5: close audit overlay via its Close button ───────────────
    await page.locator(".ind-audit-overlay button", { hasText: /Close/ }).click();
    await page.waitForTimeout(300);
    await asserts(audit, "stage5: audit overlay closed",
      async () => await expect(page.locator(".ind-audit-overlay")).toHaveCount(0));

    // ── Stage 6: edit a paragraph → captureEdit POST ────────────────────
    const para = page.locator(".tiptap-paragraph").first();
    await para.click();
    await page.keyboard.press("End");
    await page.keyboard.type(" — edited by IND-HAPPY");
    await page.locator(".ind-doc-head").click();  // blur
    await page.waitForTimeout(400);
    await shot(page, "IND-HAPPY", "04_after_edit", audit);
    await asserts(audit, "stage6: edit POST fired with diff", () => {
      const event = audit.feedbackEvents.find((e) => e.surface === "edit");
      expect(event).toBeTruthy();
      expect((event?.request_payload.edited as string).length).toBeGreaterThan(
        (event?.request_payload.original as string).length
      );
    });

    // ── Stage 7: suggest a citation → captureCitation POST ──────────────
    await page.locator(".cite-add").first().click();
    await page.locator(".cite-popover input").first().fill("ICH M3(R2) §1.5");
    await page.locator(".cite-popover textarea").fill("FIH dose justification");
    await page.locator(".cite-popover button.primary").click();
    await page.waitForTimeout(400);
    await asserts(audit, "stage7: cite POST fired with document_only=false", () => {
      const event = audit.feedbackEvents.find((e) => e.surface === "cite");
      expect(event).toBeTruthy();
      expect(event?.request_payload.document_only).toBe(false);
    });

    // ── Stage 8: regenerate-with-instruction → captureRegenerate POST ───
    const regenBtn = page.locator(".regen-btn").first();
    if (await regenBtn.count() > 0) {
      await regenBtn.click();
      await page.waitForSelector(".modal", { timeout: 2000 });
      await page.locator(".modal input[type=radio]").nth(1).check();
      await page.locator(".modal textarea").fill("Tighten AFE direction comment.");
      await page.locator(".modal button.primary").click();
      await page.waitForTimeout(400);
      await asserts(audit, "stage8: regenerate POST fired with instruction", () => {
        const event = audit.feedbackEvents.find((e) => e.surface === "regenerate");
        expect(event).toBeTruthy();
        expect(event?.request_payload.instruction).toContain("AFE");
      });
    }

    // ── Stage 9: open Sign overlay; verify TOTP gate ────────────────────
    const sign = page.locator(".ind-step-actions .ind-btn.warn, .ind-step-actions .ind-btn.primary").first();
    await sign.click();
    await page.waitForSelector(".sign-overlay");
    await shot(page, "IND-HAPPY", "05_sign_overlay", audit);
    await asserts(audit, "stage9: Sign overlay shows 21 CFR Part 11",
      async () => await expect(page.locator(".sign-head .sub")).toContainText("21 CFR Part 11"));
    await asserts(audit, "stage9: Sign button disabled before TOTP",
      async () => await expect(page.locator(".sign-foot .ind-btn.primary")).toBeDisabled());

    const totps = page.locator(".totp-input input");
    for (let i = 0; i < 6; i++) await totps.nth(i).fill(String((i + 1) % 10));
    await asserts(audit, "stage9: Sign button enabled after TOTP complete",
      async () => await expect(page.locator(".sign-foot .ind-btn.primary")).toBeEnabled());

    audit.auditCountsEnd = await readAuditCounts(page);
    finalize(audit, "passed");
  } catch (err) {
    finalize(audit, "failed", err as Error);
    throw err;
  }
});
