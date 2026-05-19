/**
 * Research-Agent v2 sandbox — comprehensive E2E
 *
 * The sandbox under test is `frontend/research_agent_v2/`, a single-page
 * React app served by `python3 -m http.server 8765`. No backend, no auth,
 * no DB — everything driven by URL params + window.SseAdapter.
 *
 * Test plan: docs/20260519_research_agent_v2_test_plan.md
 *
 * 22 tests across 6 groups:
 *   A. URL & mode wiring             RA-1 .. RA-3
 *   B. SSE adapter contract          RA-4 .. RA-7
 *   C. Plan checklist                RA-8 .. RA-10
 *   D. Chat thread                   RA-11 .. RA-14
 *   E. Cards                         RA-15 .. RA-18
 *   F. Live-mode diagnostics         RA-19 .. RA-22
 *
 * Pattern: cribbed from cryoem-stepwise-and-output.e2e.ts (SuiteRecord
 * audit, `assert(rec, name, condition, note)`, screenshots, audit JSON).
 *
 * Output: e2e/screenshots/research_agent_v2/{RA-XX__*.png, audit_*.json}
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SANDBOX_URL = process.env.RAV2_URL || "http://127.0.0.1:8765/index.html";
const SS_DIR = path.join(__dirname, "screenshots", "research_agent_v2");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const SCENARIOS = ["drugscreen", "cryosparc", "rnaseq", "variant"] as const;
type Scenario = typeof SCENARIOS[number];

// ---------------------------------------------------------------------------
// Audit types — mirror the cryo suite shape for consistency
// ---------------------------------------------------------------------------
interface RunRecord {
  testId: string;
  scenario?: string;
  startTs: number;
  endTs: number;
  assertions: { name: string; passed: boolean; note?: string }[];
  screenshots: string[];
  jsErrors: string[];
}

const SUITE_AUDIT: RunRecord[] = [];

function mkRec(testId: string, scenario?: string): RunRecord {
  return { testId, scenario, startTs: Date.now(), endTs: 0, assertions: [], screenshots: [], jsErrors: [] };
}

function assert(rec: RunRecord, name: string, condition: boolean, note?: string): void {
  rec.assertions.push({ name, passed: !!condition, note });
  if (!condition) console.warn(`[ASSERT FAIL] ${rec.testId} :: ${name}${note ? ` — ${note}` : ""}`);
}

async function shot(page: Page, rec: RunRecord, slug: string): Promise<void> {
  const file = path.join(SS_DIR, `${rec.testId}__${slug}.png`);
  await page.screenshot({ path: file, fullPage: false }).catch(() => {});
  rec.screenshots.push(file);
}

function attachErrorTrap(page: Page, rec: RunRecord): void {
  page.on("pageerror", (e) => rec.jsErrors.push(String(e)));
  page.on("crash", () => rec.jsErrors.push("page crashed"));
}

function url(params: Record<string, string>): string {
  const q = new URLSearchParams(params).toString();
  return `${SANDBOX_URL}?${q}`;
}

// Wait for the sandbox to finish booting + first chat content to render.
async function bootSandbox(page: Page, params: Record<string, string>): Promise<void> {
  await page.goto(url(params), { waitUntil: "networkidle" });
  // The thread header is the cheapest "app mounted" signal.
  await page.waitForSelector('.chat-top, .title', { state: "visible", timeout: 10_000 }).catch(() => {});
}

// Helper — read the live status pill text (real-mode only).
async function liveStatusText(page: Page): Promise<string | null> {
  return await page.evaluate(() => {
    const m = (document.body.innerText || "").match(/SSE:\s*\S+(?:\s*·[^\n]+)?/);
    return m ? m[0] : null;
  });
}

// Helper — count plan items and their statuses.
async function readPlan(page: Page): Promise<{ total: number; done: number; running: number; warn: number }> {
  return await page.evaluate(() => {
    const items = Array.from(document.querySelectorAll('[class*="plan-item"]'));
    const stats = { total: items.length, done: 0, running: 0, warn: 0 };
    for (const el of items) {
      const klass = (el as HTMLElement).className.toLowerCase();
      if (klass.includes('done') || klass.includes('completed')) stats.done += 1;
      else if (klass.includes('running')) stats.running += 1;
      else if (klass.includes('warn')) stats.warn += 1;
    }
    return stats;
  });
}

// ---------------------------------------------------------------------------
// Suite-level lifecycle
// ---------------------------------------------------------------------------
test.afterAll(() => {
  const out = path.join(SS_DIR, `audit_${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  const passed = SUITE_AUDIT.filter(r => r.assertions.every(a => a.passed) && r.jsErrors.length === 0).length;
  const summary = {
    suiteId: "research_agent_v2_sandbox",
    generatedAt: new Date().toISOString(),
    passed,
    total: SUITE_AUDIT.length,
    runs: SUITE_AUDIT,
  };
  fs.writeFileSync(out, JSON.stringify(summary, null, 2));
  console.log(`[Audit] ${passed}/${summary.total} → ${out}`);
});

// ===========================================================================
// Group A — URL & mode wiring
// ===========================================================================

test("RA-1: sandbox boots in ?live=mock with no JS errors and SseAdapter exposed", async ({ page }) => {
  const rec = mkRec("RA-1");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    const adapter = await page.evaluate(() => ({
      hasAdapter:           typeof (window as any).SseAdapter === 'object',
      hasMockFactory:       typeof (window as any).SseAdapter?.createMockBiomateStream === 'function',
      hasRealFactory:       typeof (window as any).SseAdapter?.connectRealBiomateStream === 'function',
      tapeKeys:             Object.keys((window as any).SseAdapter?.TAPES || {}),
    }));
    assert(rec, "SseAdapter present",           adapter.hasAdapter);
    assert(rec, "mock factory exposed",         adapter.hasMockFactory);
    assert(rec, "real factory exposed",         adapter.hasRealFactory);
    assert(rec, "tape keys include all 4",      ["drugscreen","cryoem","rnaseq","variant"].every(k => adapter.tapeKeys.includes(k)),
                                                JSON.stringify(adapter.tapeKeys));
    await shot(page, rec, "loaded");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-2: no ?live= falls back to tape engine and still renders the welcome thread", async ({ page }) => {
  const rec = mkRec("RA-2");
  attachErrorTrap(page, rec);
  try {
    await page.goto(SANDBOX_URL, { waitUntil: "networkidle" });
    await page.waitForTimeout(2000);
    const hasTitle = await page.locator(".title").first().isVisible().catch(() => false);
    assert(rec, "thread title visible without ?live", hasTitle);
    const noStatusPill = await page.evaluate(() => !/SSE:/.test(document.body.innerText));
    assert(rec, "no SSE pill in tape mode", noStatusPill);
    await shot(page, rec, "tape-mode");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-3: bad scenario in ?live=mock falls back gracefully to a valid scenario", async ({ page }) => {
  const rec = mkRec("RA-3");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "bogus_no_tape" });
    await page.waitForTimeout(2000);
    const hasTitle = await page.locator(".title").first().isVisible().catch(() => false);
    assert(rec, "page renders despite bad scenario", hasTitle);
    // ResearchApp falls back to init.scenarioId when the URL value isn't in
    // RESEARCH_SCENARIOS; a chat thread should still render.
    const txt = await page.evaluate(() => document.body.innerText);
    assert(rec, "fell back to a valid scenario (some chat content)", txt.length > 200);
    await shot(page, rec, "bad-scenario");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

// ===========================================================================
// Group B — SSE adapter contract
// ===========================================================================

test("RA-4: SseAdapter.deriveSpeaker returns canonical speaker pills per prefix", async ({ page }) => {
  const rec = mkRec("RA-4");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    const map = await page.evaluate(() => {
      const ds = (window as any).SseAdapter.deriveSpeaker;
      return {
        qc:    ds('workflow.qc_gate_warning'),
        qcB:   ds('workflow.qc_gate_blocked'),
        loop:  ds('workflow.autoloop_started'),
        wf:    ds('workflow.phase_started'),
        agent: ds('deepagent.start'),
        plan:  ds('plan.shown'),
        find:  ds('findings.generated'),
        other: ds('something.else'),
      };
    });
    assert(rec, "qc gate → qc",         map.qc === 'qc' && map.qcB === 'qc');
    assert(rec, "autoloop → loop",      map.loop === 'loop');
    assert(rec, "workflow.* → wf",      map.wf === 'wf');
    assert(rec, "deepagent → agent",    map.agent === 'agent');
    assert(rec, "plan → plan",          map.plan === 'plan');
    assert(rec, "findings → find",      map.find === 'find');
    assert(rec, "unknown → wf",         map.other === 'wf');
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-5: SseAdapter.renderFriendly produces templated strings for documented kinds", async ({ page }) => {
  const rec = mkRec("RA-5");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    const strings = await page.evaluate(() => {
      const rf = (window as any).SseAdapter.renderFriendly;
      return {
        phase_started: rf('workflow.phase_started', { phase_name: 'STAR alignment', n: 2, of: 5 }),
        phase_done:    rf('workflow.phase_completed', { phase_name: 'STAR alignment', detail: '91.4% mapped' }),
        qc_warn:       rf('workflow.qc_gate_warning', { metric: 'hERG_fail_rate', value: 0.18, threshold: 0.10 }),
        qc_block:      rf('workflow.qc_gate_blocked', { metric: 'hERG_fail_rate' }),
        autoloop:      rf('workflow.autoloop_started', { changes: { logp_max: 4.5, mw_max_da: 480 } }),
        completed:     rf('workflow.completed', { steps_succeeded: 5, steps_total: 5 }),
        submitted:     rf('workflow.submitted', {}),
        pilot:         rf('workflow.pilot_started', { sampled: 500 }),
      };
    });
    assert(rec, "phase_started filled",   /Step 2\/5: STAR alignment/.test(strings.phase_started));
    assert(rec, "phase_completed filled", /STAR alignment done — 91\.4% mapped/.test(strings.phase_done));
    assert(rec, "qc_warning filled",      /QC flagged hERG_fail_rate = 0\.18 \(threshold 0\.1\)/.test(strings.qc_warn));
    assert(rec, "qc_blocked filled",      /QC blocked on hERG_fail_rate/.test(strings.qc_block));
    assert(rec, "autoloop filled",        /Trying again with logp_max=4\.5/.test(strings.autoloop));
    assert(rec, "completed filled",       /Workflow finished\. 5\/5 steps succeeded/.test(strings.completed));
    assert(rec, "submitted templated",    /starting your workflow/i.test(strings.submitted));
    assert(rec, "pilot started templated",/quick pilot on 500 samples/i.test(strings.pilot));
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-6: regression — spread pattern {...e('K'), technical:{…}} yields filled friendly_message (non-stale)", async ({ page }) => {
  const rec = mkRec("RA-6");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    // Verify makeEvent's friendly_message is a non-enumerable getter, so the
    // spread doesn't carry a stale string — and that the mock emitter computes
    // it at send time from the final `technical`.
    const observations = await page.evaluate(() => {
      const me = (window as any).SseAdapter.makeEvent;
      const ev = me('workflow.phase_started', 'inv-1', null);
      const desc = Object.getOwnPropertyDescriptor(ev, 'friendly_message');
      const spread = { ...ev, technical: { phase_name: 'STAR', n: 2, of: 5 } };
      return {
        descEnumerable: !!desc?.enumerable,
        descHasGet:     typeof desc?.get === 'function',
        // After spread, friendly_message should NOT be copied (because the
        // descriptor is non-enumerable). The mock emitter materializes it at
        // send time. So on the spread object the property is absent.
        spreadHasFM:    Object.prototype.hasOwnProperty.call(spread, 'friendly_message'),
        spreadFMValue:  (spread as any).friendly_message,
      };
    });
    assert(rec, "friendly_message is a getter",        observations.descHasGet);
    assert(rec, "friendly_message is non-enumerable",  observations.descEnumerable === false);
    assert(rec, "spread does NOT copy friendly_message", observations.spreadHasFM === false);
    assert(rec, "no stale 'Step step…' carried",       observations.spreadFMValue === undefined);
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-7: connectRealBiomateStream emits onStatus(connecting, …) immediately and (error, …) on failure", async ({ page }) => {
  const rec = mkRec("RA-7");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    const log = await page.evaluate(async () => {
      const status: any[] = [];
      const stream = (window as any).SseAdapter.connectRealBiomateStream('inv-bogus-7', {
        onStatus: (s: string, d: any) => status.push({ s, d }),
      });
      const handle = stream.start(() => {});
      await new Promise(r => setTimeout(r, 1500));
      handle.close();
      return { status, urlAttempted: stream.url };
    });
    assert(rec, "first status is 'connecting'",
           log.status[0]?.s === 'connecting',
           JSON.stringify(log.status));
    assert(rec, "connecting carries URL",
           typeof log.status[0]?.d === 'string' && /\/api\/workflows\/inv-bogus-7\/events$/.test(log.status[0].d));
    assert(rec, "error status follows since no backend",
           log.status.some((x: any) => x.s === 'error'),
           JSON.stringify(log.status));
    assert(rec, "stream.url exposes endpoint",
           /\/api\/workflows\/inv-bogus-7\/events$/.test(log.urlAttempted || ''));
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

// ===========================================================================
// Group C — Plan checklist (parametrized across scenarios)
// ===========================================================================

for (const sc of SCENARIOS) {
  test(`RA-8/${sc}: plan checklist reaches 5/5 done with scenario-specific titles`, async ({ page }) => {
    const rec = mkRec("RA-8", sc);
    attachErrorTrap(page, rec);
    try {
      await bootSandbox(page, { live: "mock", scenario: sc, speed: "5" });
      // Wait for the full mock tape to play out at speed=5 → ~3–4s.
      await page.waitForTimeout(8000);
      const stats = await readPlan(page);
      assert(rec, "5 plan items", stats.total === 5, `total=${stats.total}`);
      assert(rec, "5 done at completion", stats.done === 5, `done=${stats.done}`);
      // Per-scenario expected titles
      const expected: Record<Scenario, string[]> = {
        drugscreen: ['Ingest compounds','ADMET prediction','hERG gate','Ames + DILI gates','Composite ranking'],
        cryosparc:  ['Motion Correction','Particle Picking','2D Classification','3D Reconstruction','Validation'],
        rnaseq:     ['FastQC + trimming','STAR alignment','Salmon quantification','DESeq2','GO + pathway enrichment'],
        variant:    ['Reference indexing','BWA-MEM2 alignment','BQSR recalibration','HaplotypeCaller','VQSR + annotation'],
      };
      const txt = await page.evaluate(() => document.body.innerText);
      for (const exp of expected[sc]) {
        assert(rec, `plan item contains: ${exp}`, txt.includes(exp));
      }
      await shot(page, rec, `${sc}-plan-done`);
    } finally {
      rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
      expect(rec.jsErrors).toEqual([]);
      expect(rec.assertions.every(a => a.passed)).toBe(true);
    }
  });
}

test("RA-9: plan progress increments — at least one mid-run snapshot has a running item", async ({ page }) => {
  const rec = mkRec("RA-9");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "rnaseq", speed: "1" });
    // Sample plan state every 600ms over ~6s — at least one should have running > 0.
    let everRunning = false;
    let everPartial = false;
    for (let i = 0; i < 10; i++) {
      await page.waitForTimeout(600);
      const s = await readPlan(page);
      if (s.running > 0) everRunning = true;
      if (s.done > 0 && s.done < 5) everPartial = true;
    }
    assert(rec, "saw at least one mid-run 'running' item",  everRunning);
    assert(rec, "saw at least one partial-complete state",  everPartial);
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-10: variant scenario shows transient 'warn' on BWA-MEM2 alignment (advisory)", async ({ page }) => {
  const rec = mkRec("RA-10");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "variant", speed: "1" });
    let everWarn = false;
    for (let i = 0; i < 18; i++) {
      await page.waitForTimeout(500);
      const s = await readPlan(page);
      if (s.warn > 0) everWarn = true;
      if (everWarn && s.done >= 5) break;
    }
    assert(rec, "advisory warn surfaced", everWarn);
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

// ===========================================================================
// Group D — Chat thread
// ===========================================================================

test("RA-11: speaker pills present — WF / QC / AGENT / LOOP all rendered for drugscreen", async ({ page }) => {
  const rec = mkRec("RA-11");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    await page.waitForTimeout(8000);
    const pillsText = await page.evaluate(() => {
      // Expand any collapsed groups so all pills become visible
      const collapsers = Array.from(document.querySelectorAll('[class*="collapse"]')) as HTMLElement[];
      collapsers.forEach(el => el.click?.());
      const pills = Array.from(document.querySelectorAll('[class*="speaker"], [class*="pill"]'))
        .map(el => (el as HTMLElement).innerText.trim())
        .filter(t => t.length > 0 && t.length < 12);
      return pills.join('|').toUpperCase();
    });
    assert(rec, "WF pill present",     /\bWF\b/.test(pillsText),     pillsText);
    assert(rec, "QC pill present",     /\bQC\b/.test(pillsText),     pillsText);
    assert(rec, "AGENT pill present",  /\bAGENT\b/.test(pillsText),  pillsText);
    assert(rec, "LOOP pill present",   /\bLOOP\b/.test(pillsText),   pillsText);
    await shot(page, rec, "speaker-pills");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-12: friendly messages are templated — no generic 'Step step…' or 'QC flagged metric.'", async ({ page }) => {
  const rec = mkRec("RA-12");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "variant", speed: "1" });
    await page.waitForTimeout(15000);
    // Expand all collapsed groups
    const collapsers = page.locator('[class*="collapse"]');
    const cn = await collapsers.count();
    for (let i = 0; i < cn; i++) { await collapsers.nth(i).click({ trial: false }).catch(() => {}); }
    const body = await page.evaluate(() => document.body.innerText);
    assert(rec, "no 'Step step…' fallback",       !/Step step…/.test(body));
    assert(rec, "no 'QC flagged metric.' fallback", !/QC flagged metric\./.test(body));
    assert(rec, "templated step text appears",     /Step \d\/5: [A-Z]/.test(body));
    assert(rec, "templated QC mapping_rate text",  /mapping_rate\s*=\s*0\.948/.test(body));
    assert(rec, "templated completion text",       /Workflow finished\. 5\/5 steps succeeded/.test(body));
    await shot(page, rec, "templated-messages");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-13: chat shows collapse marker when same-speaker events exceed threshold", async ({ page }) => {
  const rec = mkRec("RA-13");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "rnaseq", speed: "5" });
    await page.waitForTimeout(8000);
    const body = await page.evaluate(() => document.body.innerText);
    assert(rec, "collapse marker visible",  /earlier updates · click to show/i.test(body));
    await shot(page, rec, "collapse-marker");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-14: 'Workflow finished. 5/5 steps succeeded.' line present at completion (regression)", async ({ page }) => {
  const rec = mkRec("RA-14");
  attachErrorTrap(page, rec);
  try {
    for (const sc of SCENARIOS) {
      await bootSandbox(page, { live: "mock", scenario: sc, speed: "5" });
      await page.waitForTimeout(8000);
      const body = await page.evaluate(() => document.body.innerText);
      const expected = sc === "cryosparc"
        ? /Workflow finished\. 23\/23 steps succeeded/
        : /Workflow finished\. 5\/5 steps succeeded/;
      assert(rec, `${sc}: completion text filled`, expected.test(body));
    }
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

// ===========================================================================
// Group E — Cards
// ===========================================================================

test("RA-15: drugscreen — PilotPromptCard appears early with sampled / total / runtime details", async ({ page }) => {
  const rec = mkRec("RA-15");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "1" });
    // Pilot prompt should appear around 1.6s (200+800+600 → 1600ms cumulative at speed=1)
    await page.waitForTimeout(2500);
    const body = await page.evaluate(() => document.body.innerText);
    assert(rec, "pilot card title",          /pilot/i.test(body));
    assert(rec, "10000 sample size shown",   /10000|10,?000/.test(body));
    assert(rec, "500 pilot subset shown",    /500/.test(body));
    assert(rec, "fraction or '5%'",          /5\s*%|\.05/.test(body));
    await shot(page, rec, "pilot-prompt");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-16: drugscreen — PilotPromotionCard renders 'fail' result with QC gate list + suggestion", async ({ page }) => {
  const rec = mkRec("RA-16");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    await page.waitForTimeout(5000);
    const body = await page.evaluate(() => document.body.innerText);
    assert(rec, "fail result shown",                  /fail/i.test(body));
    assert(rec, "hERG QC row",                        /hERG/.test(body));
    assert(rec, "Ames QC row",                        /Ames/.test(body));
    assert(rec, "DILI QC row (pass)",                 /DILI/.test(body));
    assert(rec, "suggestion contains logp_max",       /logp_max/.test(body));
    assert(rec, "suggestion contains mw_max_da",      /mw_max_da/.test(body));
    await shot(page, rec, "pilot-promotion");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-17: drugscreen — ComparisonCard renders Run A vs Run B with autoloop param diff + p-value recommendation", async ({ page }) => {
  const rec = mkRec("RA-17");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    await page.waitForTimeout(10000);
    const body = await page.evaluate(() => document.body.innerText);
    assert(rec, "Run A / Run B headers",         /Run A.*Run B/s.test(body));
    assert(rec, "hERG fail-rate row",            /hERG fail-rate/.test(body));
    assert(rec, "Ames fail-rate row",            /Ames fail-rate/.test(body));
    assert(rec, "Candidate count row",           /Candidate count/.test(body));
    assert(rec, "Runtime row",                   /Runtime/.test(body));
    assert(rec, "autoloop tag visible",          /autoloop/.test(body));
    assert(rec, "logp_max old→new (5.5→4.5)",    /5\.5.*4\.5/.test(body));
    assert(rec, "mw_max_da old→new (600→480)",   /600.*480/.test(body));
    assert(rec, "p-value 0.008 shown",           /p\s*0\.008|0\.008/.test(body));
    assert(rec, "Recommendation text present",   /Recommendation/i.test(body));
    await shot(page, rec, "comparison-card");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-18: each scenario produces a FindingsChatCard with scenario-specific title", async ({ page }) => {
  const rec = mkRec("RA-18");
  attachErrorTrap(page, rec);
  try {
    const expected: Record<Scenario, RegExp> = {
      drugscreen: /47 BBB-penetrant candidates/,
      cryosparc:  /3\.1 Å reconstruction.*publication-ready/,
      rnaseq:     /1,847 DEGs.*23 enriched pathways/,
      variant:    /3\.84M PASS variants.*ts\/tv 2\.04/,
    };
    for (const sc of SCENARIOS) {
      await bootSandbox(page, { live: "mock", scenario: sc, speed: "5" });
      await page.waitForTimeout(10000);
      const body = await page.evaluate(() => document.body.innerText);
      assert(rec, `${sc}: findings title`, expected[sc].test(body));
      await shot(page, rec, `${sc}-findings`);
    }
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

// ===========================================================================
// Group F — Live-mode diagnostics
// ===========================================================================

test("RA-19: ?live=real with no ?inv shows SSE error pill with tooltip", async ({ page }) => {
  const rec = mkRec("RA-19");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "real" });
    await page.waitForTimeout(1500);
    const text = await liveStatusText(page);
    assert(rec, "SSE pill visible",          !!text, text || '');
    assert(rec, "SSE pill shows error",      !!text && /SSE:\s*error/.test(text), text || '');
    await shot(page, rec, "real-no-inv");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-20: ?live=real&inv=bogus transitions through connecting → error", async ({ page }) => {
  const rec = mkRec("RA-20");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "real", inv: "bogus-test-inv" });
    // Polling — first 'connecting' may flicker very briefly
    await page.waitForTimeout(2500);
    const text = await liveStatusText(page);
    assert(rec, "SSE pill visible",     !!text, text || '');
    assert(rec, "ends in error state",  !!text && /SSE:\s*error/.test(text), text || '');
    await shot(page, rec, "real-bogus-inv");
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-21: mock mode does NOT render the SSE pill (real-mode only)", async ({ page }) => {
  const rec = mkRec("RA-21");
  attachErrorTrap(page, rec);
  try {
    await bootSandbox(page, { live: "mock", scenario: "drugscreen", speed: "5" });
    await page.waitForTimeout(3000);
    const text = await liveStatusText(page);
    assert(rec, "no SSE pill in mock mode", text === null, `unexpected: ${text}`);
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(rec.jsErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});

test("RA-22: zero JS errors across full headless audit of all 4 scenarios", async ({ page }) => {
  const rec = mkRec("RA-22");
  const allErrors: string[] = [];
  page.on("pageerror", e => allErrors.push(String(e)));
  try {
    for (const sc of SCENARIOS) {
      await bootSandbox(page, { live: "mock", scenario: sc, speed: "5" });
      await page.waitForTimeout(7000);
    }
    assert(rec, "no JS errors across 4 scenarios", allErrors.length === 0, allErrors.slice(0, 3).join(" | "));
    rec.jsErrors = allErrors;
  } finally {
    rec.endTs = Date.now(); SUITE_AUDIT.push(rec);
    expect(allErrors).toEqual([]);
    expect(rec.assertions.every(a => a.passed)).toBe(true);
  }
});
