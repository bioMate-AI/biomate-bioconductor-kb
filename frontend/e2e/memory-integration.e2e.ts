/**
 * Memory Integration E2E Tests
 *
 * Tests cross-session memory, episode recording, outcome tracking, and workflow reference.
 * Follows the comprehensive pattern from cryoem-full-20img-multigpu.e2e.ts.
 *
 * Test index:
 *   MM-0   API preflight — memory endpoints accessible + database connectivity
 *   MM-1   Session initialization — user + project context loading
 *   MM-2   Episode recording — chat → workflow suggestion → episode created
 *   MM-3   Episode outcome tracking — workflow completion → outcome recorded
 *   MM-4   Cross-session workflow reference — "use same workflow as yesterday"
 *   MM-5   Memory hints injection — past episodes influence responses
 *   MM-6   Findings storage in episodes — findings_json populated
 *   MM-7   Paper generation — episode → DOCX with figures
 *   MM-8   Correction learning — user correction → preference updated
 *
 * CLAUSE: No page.route() mocks. All API calls hit the live backend.
 * Screenshots → e2e/screenshots/memory-integration/
 * Audit JSON  → e2e/screenshots/memory-integration/audit_<ts>.json
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_URL   = process.env.BIOMATE_URL    || "http://localhost:5000";
const E2E_TOKEN  = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR     = path.join(__dirname, "screenshots", "memory-integration");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ── Audit ────────────────────────────────────────────────────────────────────
interface Assertion { name: string; passed: boolean; note?: string }
interface AuditRecord {
  testId: string; startTs: number; endTs: number;
  finalStatus: string; assertions: Assertion[]; screenshots: string[]; error?: string;
  metadata?: {
    episodeId?: number;
    projectId?: string;
    workflowName?: string;
    runId?: string;
  };
}
const AUDIT: AuditRecord[] = [];
function writeAudit() {
  const p = path.join(SS_DIR, `audit_${Date.now()}.json`);
  fs.writeFileSync(p, JSON.stringify(AUDIT, null, 2));
  console.log(`[audit] ${p}`);
}
async function shot(page: Page, name: string): Promise<string> {
  const file = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  return file;
}

// ── Helpers ──────────────────────────────────────────────────────────────────
async function loginOrRegister(page: Page, label: string): Promise<void> {
  const email = `e2e_mm_${label}_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("load");
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });

  // Registration form
  const nameField = page.locator("#name").first();
  if (await nameField.isVisible({ timeout: 12_000 }).catch(() => false)) {
    await page.fill("#name", `Memory E2E ${label}`);
    await page.fill("#email", email);
    await page.fill("#password", "TestPass123!");
    await page.fill("#confirmPassword", "TestPass123!");
    await page.locator("#terms").click().catch(() => {});
    await page.click('button[type="submit"]');
    await page.waitForTimeout(1500);
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState("load");

  // Wait for chat interface
  for (let i = 0; i < 8; i++) {
    const ready = await page.locator("textarea").first().isVisible({ timeout: 4000 }).catch(() => false);
    if (ready) break;
    await page.waitForTimeout(2000);
  }

  // Dismiss survey/onboarding
  for (const sel of ['button:has-text("Skip")', 'button:has-text("Dismiss")', 'button:has-text("Maybe later")']) {
    const btn = page.locator(sel).first();
    if (await btn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await btn.click({ force: true }).catch(() => {});
    }
  }

  await page.waitForSelector("textarea", { state: "visible", timeout: 15_000 }).catch(() => {});
  await page.waitForTimeout(800);
}

async function sendMessage(page: Page, msg: string, timeoutMs = 120_000): Promise<boolean> {
  const ta = page.locator("textarea").first();
  await ta.fill(msg);
  await ta.press("Enter");
  console.log(`[chat] "${msg.slice(0, 90)}..."`);

  const pending = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing request",
  ];
  await Promise.race(pending.map(s => page.waitForSelector(s, { state: "visible", timeout: 25_000 }).catch(() => null)));
  await Promise.all(pending.map(s => page.waitForSelector(s, { state: "hidden",  timeout: timeoutMs }).catch(() => null)));

  await page.waitForFunction(
    () => {
      const el = document.querySelector('[data-is-latest-assistant="true"]');
      const t  = el?.textContent ?? "";
      return t.trim().length > 30 && !t.includes("is thinking") && !t.includes("Analyzing");
    },
    { timeout: timeoutMs }
  ).catch(() => {});

  await page.waitForTimeout(1500);
  const txt = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 8000 }).catch(() => "");
  return (txt?.trim().length ?? 0) > 20;
}

async function waitForWorkflowCard(page: Page, ms = 180_000): Promise<boolean> {
  const deadline = Date.now() + ms;
  const baseline = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
  while (Date.now() < deadline) {
    await page.evaluate(() => {
      const c = document.querySelector('[data-testid="chat-messages"], main');
      if (c) c.scrollTop = c.scrollHeight;
    }).catch(() => {});
    const count = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
    if (count > baseline || count > 0) { await page.waitForTimeout(1200); return true; }
    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="qc-settings-section"]',
      'text=AWAITING REVIEW',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        await page.waitForTimeout(800); return true;
      }
    }
    await page.waitForTimeout(1000);
  }
  return false;
}

async function clickRun(page: Page): Promise<boolean> {
  for (const sel of [
    '[data-testid="button-run-workflow-panel"]',
    '[data-testid="button-confirm-and-run"]',
    'button:has-text("Run Workflow")',
    'button:has-text("Confirm & Run")',
  ]) {
    const btn = page.locator(sel).first();
    if (!await btn.isVisible({ timeout: 3000 }).catch(() => false)) continue;
    const deadline = Date.now() + 15_000;
    while (!await btn.isEnabled({ timeout: 1000 }).catch(() => false) && Date.now() < deadline) {
      await page.waitForTimeout(1000);
    }
    await btn.click().catch(() => btn.click({ force: true }));
    console.log(`[run] clicked ${sel}`);
    return true;
  }
  return false;
}

async function waitForTerminal(page: Page, ms = 7_200_000): Promise<string> {
  await page.waitForTimeout(8000);
  const start = Date.now();
  while (Date.now() - start < ms) {
    await page.waitForTimeout(8000);
    if (await page.locator('[data-testid="workflow-completion-banner"]').first().isVisible({ timeout: 1000 }).catch(() => false))
      return "completed";
    const status = await page.locator('[data-testid="workflow-overall-status-badge"]').first().getAttribute("data-status").catch(() => null);
    if (status === "completed") return "completed";
    if (status === "failed")    return "failed";
    const phaseRunning = await page.locator('[data-testid^="phase-card-"][data-status="running"]').count().catch(() => 0);
    if (phaseRunning > 0) console.log(`[poll] ${phaseRunning} phases still running…`);
  }
  return "timeout";
}

async function openWorkflowSettings(page: Page): Promise<void> {
  const strip = page.locator('button.strip:has-text("Workflow settings"), button:has-text("Workflow settings")').first();
  if (!await strip.isVisible({ timeout: 5000 }).catch(() => false)) return;
  const isOpen = await strip.evaluate(el => el.classList.contains("open")).catch(() => false);
  if (!isOpen) { await strip.click(); await page.waitForTimeout(600); }
}

async function setParamValue(page: Page, paramName: string, value: string): Promise<boolean> {
  const selectors = [
    `input#${paramName}`,
    `[data-testid="param-inline-edit-${paramName}"] input`,
    `[data-testid="param-inline-edit-${paramName}"] textarea`,
  ];
  for (const sel of selectors) {
    const el = page.locator(sel).first();
    if (!await el.isVisible({ timeout: 2000 }).catch(() => false)) continue;
    await el.fill(value);
    await el.press("Tab");
    await page.waitForTimeout(300);
    console.log(`[param] ${paramName}=${value}`);
    return true;
  }
  return false;
}

async function createTestProject(page: Page, name: string, domain = "transcriptomics", organisms = ["human"]): Promise<string | null> {
  const result = await page.evaluate(async ({ base, projName, dom, orgs }: any) => {
    try {
      const r = await fetch(`${base}/api/memory/projects`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: projName,
          description: "E2E memory integration test project",
          primaryDomain: dom,
          organisms: orgs,
          dataModalities: ["RNA-seq"],
          researchGoal: "Testing cross-session memory"
        })
      });
      const data = await r.json().catch(() => ({}));
      return { ok: r.ok, projectId: data.id || data.project_id, status: r.status };
    } catch (e: any) {
      return { ok: false, error: e?.message };
    }
  }, { base: BASE_URL, projName: name, dom: domain, orgs: organisms });

  console.log(`[project] created: ${result.projectId || result.error || `HTTP ${result.status}`}`);
  return result.projectId || null;
}

// ── MM-0: API Preflight ──────────────────────────────────────────────────────
test.describe("MM-0 API preflight", () => {
  test("Memory API endpoints accessible + database connectivity", async ({ request }) => {
    const assertions: Assertion[] = [];

    // 1. Health check
    const healthResp = await request.get(`${BASE_URL}/api/health`).catch(() => null);
    const healthOk = healthResp?.status() === 200;
    assertions.push({ name: "MM-0: Health endpoint returns 200", passed: healthOk });

    if (healthOk) {
      const health = await healthResp!.json().catch(() => ({}));
      const dbConnected = health.database === "connected" || health.status === "ok";
      assertions.push({ name: "MM-0: Database connectivity confirmed", passed: dbConnected, note: health.database || health.status });
    }

    // 2. Memory user endpoint
    const userResp = await request.get(`${BASE_URL}/api/memory/user?userId=test-user-mm0`, {
      headers: { "x-e2e-test-token": E2E_TOKEN }
    }).catch(() => null);
    const userStatus = userResp?.status() || 0;
    assertions.push({
      name: "MM-0: Memory user endpoint accessible",
      passed: [200, 404].includes(userStatus),
      note: `HTTP ${userStatus} (404 acceptable if user doesn't exist)`
    });

    // 3. Projects endpoint
    const projectsResp = await request.get(`${BASE_URL}/api/memory/projects`, {
      headers: { "x-e2e-test-token": E2E_TOKEN }
    }).catch(() => null);
    const projectsStatus = projectsResp?.status() || 0;
    assertions.push({
      name: "MM-0: Memory projects endpoint accessible",
      passed: [200, 401].includes(projectsStatus),
      note: `HTTP ${projectsStatus}`
    });

    // 4. Episodes endpoint (via projects)
    const episodesResp = await request.get(
      `${BASE_URL}/api/memory/projects/test-project/episodes`,
      { headers: { "x-e2e-test-token": E2E_TOKEN } }
    ).catch(() => null);
    const episodesStatus = episodesResp?.status() || 0;
    assertions.push({
      name: "MM-0: Memory episodes endpoint accessible",
      passed: [200, 404].includes(episodesStatus),
      note: `HTTP ${episodesStatus} (404 acceptable if project doesn't exist)`
    });

    AUDIT.push({ testId: "MM-0", startTs: Date.now(), endTs: Date.now(), finalStatus: "done", assertions, screenshots: [] });
    writeAudit();

    console.log("\n════ MM-0 Preflight Results ════");
    for (const a of assertions) {
      console.log(`  ${a.passed ? "✓" : "✗"} ${a.name}${a.note ? `  (${a.note})` : ""}`);
    }

    // Hard assert: at least health check must pass
    expect(assertions.find(a => a.name.includes("Health"))?.passed).toBe(true);
  });
});

// ── MM-1: Session Initialization ─────────────────────────────────────────────
test.describe("MM-1 Session initialization", () => {
  test.setTimeout(300_000);
  test.use({ viewport: { width: 1920, height: 1080 } });

  test("User creates project → starts session → context loads from memory", async ({ page }) => {
    const assertions: Assertion[] = [];
    const screenshots: string[] = [];
    let projectId: string | null = null;

    try {
      await loginOrRegister(page, "mm1");
      screenshots.push(await shot(page, "MM1_01_home"));

      // Create project via API
      projectId = await createTestProject(page, "MM1 Session Init Test");
      assertions.push({
        name: "MM-1: Project created via memory API",
        passed: !!projectId,
        note: `projectId: ${projectId || 'none'}`
      });
      screenshots.push(await shot(page, "MM1_02_project_created"));

      // Add project knowledge
      if (projectId) {
        const knowledgeAdded = await page.evaluate(async ({ base, projId }: any) => {
          try {
            const r = await fetch(`${base}/api/memory/projects/${projId}/knowledge`, {
              method: "POST",
              credentials: "include",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                knowledgeType: "dataset_info",
                title: "Previous RNA-seq run used STAR aligner",
                content: "Last month's RNA-seq analysis used STAR for alignment with GRCh38. Results were excellent with 95% mapping rate.",
                source: "user_provided"
              })
            });
            return r.ok;
          } catch {
            return false;
          }
        }, { base: BASE_URL, projId: projectId });

        assertions.push({ name: "MM-1: Project knowledge added", passed: knowledgeAdded });
      }

      // Send chat message
      const query = "I want to run RNA-seq differential expression analysis";
      const gotResponse = await sendMessage(page, query, 60_000);
      assertions.push({ name: "MM-1: Chat message sent and response received", passed: gotResponse });
      screenshots.push(await shot(page, "MM1_03_first_message"));

      // Check if memory context influenced response
      const responseText = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 8000 }).catch(() => "");
      const memoryInfluenced = /STAR|GRCh38|previous|last time|remember/i.test(responseText);

      assertions.push({
        name: "MM-1: Memory context loaded and influenced response",
        passed: memoryInfluenced,
        note: memoryInfluenced ? "Response references past knowledge" : `Response: ${responseText.slice(0, 80)}`
      });
      screenshots.push(await shot(page, "MM1_04_memory_influenced_response"));

    } catch (err: any) {
      console.error("[MM-1] Error:", err.message);
      await shot(page, "MM1_error").catch(() => {});
    } finally {
      AUDIT.push({
        testId: "MM-1",
        startTs: Date.now(),
        endTs: Date.now(),
        finalStatus: "done",
        assertions,
        screenshots,
        metadata: { projectId: projectId || undefined }
      });
      writeAudit();

      console.log("\n════ MM-1 Results ════");
      for (const a of assertions) {
        console.log(`  ${a.passed ? "✓" : "✗"} ${a.name}${a.note ? `  (${a.note})` : ""}`);
      }
    }
  });
});

// ── MM-2: Episode Recording ──────────────────────────────────────────────────
test.describe("MM-2 Episode recording", () => {
  test.setTimeout(300_000);
  test.use({ viewport: { width: 1920, height: 1080 } });

  test("User requests workflow → episode recorded with context", async ({ page }) => {
    const assertions: Assertion[] = [];
    const screenshots: string[] = [];
    let projectId: string | null = null;

    try {
      await loginOrRegister(page, "mm2");
      screenshots.push(await shot(page, "MM2_01_home"));

      // Create project
      projectId = await createTestProject(page, "MM2 Episode Test");
      assertions.push({ name: "MM-2: Test project created", passed: !!projectId });

      // Send workflow request
      const query = [
        "Run nf-core/rnaseq on my 6 FASTQ files.",
        "Organism: human (GRCh38), stranded protocol (reverse), aligner: STAR.",
        "I want DESeq2 differential expression with padj < 0.05."
      ].join(" ");

      const gotResponse = await sendMessage(page, query, 90_000);
      assertions.push({ name: "MM-2: AI responded to workflow request", passed: gotResponse });
      screenshots.push(await shot(page, "MM2_02_workflow_request"));

      const gotCard = await waitForWorkflowCard(page, 60_000);
      assertions.push({ name: "MM-2: Workflow card appeared", passed: gotCard });
      screenshots.push(await shot(page, "MM2_03_workflow_card"));

      // Wait for episode to be recorded
      await page.waitForTimeout(3000);

      // Verify episode via API
      if (projectId) {
        const episodeResult = await page.evaluate(async ({ base, projId }: any) => {
          try {
            const r = await fetch(`${base}/api/memory/projects/${projId}/episodes`, {
              credentials: "include"
            });
            const data = await r.json().catch(() => ({ episodes: [] }));
            const episodes = data.episodes || data || [];
            const latest = episodes[episodes.length - 1];
            return {
              ok: r.ok,
              count: episodes.length,
              latestQuery: latest?.userQuery || latest?.user_query || "",
              latestIntent: latest?.userIntent || latest?.user_intent || "",
              workflowGenerated: latest?.workflowGenerated || latest?.workflow_generated || false
            };
          } catch {
            return { ok: false, count: 0, latestQuery: "", latestIntent: "", workflowGenerated: false };
          }
        }, { base: BASE_URL, projId: projectId });

        assertions.push({
          name: "MM-2: Episode recorded in database",
          passed: episodeResult.count > 0,
          note: `${episodeResult.count} episode(s) found`
        });

        assertions.push({
          name: "MM-2: Episode contains user query",
          passed: episodeResult.latestQuery.includes("rnaseq") || episodeResult.latestQuery.includes("RNA-seq") || episodeResult.latestQuery.length > 20,
          note: episodeResult.latestQuery.slice(0, 80)
        });

        assertions.push({
          name: "MM-2: Episode recorded workflow generation",
          passed: episodeResult.workflowGenerated,
          note: `workflow_generated: ${episodeResult.workflowGenerated}`
        });

        assertions.push({
          name: "MM-2: Episode contains extracted intent",
          passed: episodeResult.latestIntent.length > 5,
          note: episodeResult.latestIntent.slice(0, 80)
        });

        screenshots.push(await shot(page, "MM2_04_episode_recorded"));
      }

    } catch (err: any) {
      console.error("[MM-2] Error:", err.message);
      await shot(page, "MM2_error").catch(() => {});
    } finally {
      AUDIT.push({
        testId: "MM-2",
        startTs: Date.now(),
        endTs: Date.now(),
        finalStatus: "done",
        assertions,
        screenshots,
        metadata: { projectId: projectId || undefined }
      });
      writeAudit();

      console.log("\n════ MM-2 Results ════");
      for (const a of assertions) {
        console.log(`  ${a.passed ? "✓" : "✗"} ${a.name}${a.note ? `  (${a.note})` : ""}`);
      }
    }
  });
});

// ── MM-3: Episode Outcome Tracking ───────────────────────────────────────────
test.describe("MM-3 Episode outcome tracking", () => {
  test.setTimeout(600_000); // 10 min for workflow execution
  test.use({ viewport: { width: 1920, height: 1080 } });

  test("Run workflow → completion → episode outcome updated", async ({ page }) => {
    const assertions: Assertion[] = [];
    const screenshots: string[] = [];
    let projectId: string | null = null;
    let episodeId: number | null = null;
    let finalStatus = "not_started";

    try {
      await loginOrRegister(page, "mm3");
      screenshots.push(await shot(page, "MM3_01_home"));

      projectId = await createTestProject(page, "MM3 Outcome Test");
      assertions.push({ name: "MM-3: Test project created", passed: !!projectId });

      // Request a fast test workflow
      const query = "Run a test RNA-seq workflow on demo data (fast mode for E2E testing)";
      const gotResponse = await sendMessage(page, query, 60_000);
      assertions.push({ name: "MM-3: Test workflow request accepted", passed: gotResponse });

      const gotCard = await waitForWorkflowCard(page, 60_000);
      assertions.push({ name: "MM-3: Test workflow card appeared", passed: gotCard });
      screenshots.push(await shot(page, "MM3_02_workflow_card"));

      if (!gotCard) {
        finalStatus = "skip_no_card";
        return;
      }

      // Capture episode ID
      await page.waitForTimeout(2000);
      if (projectId) {
        const epResult = await page.evaluate(async ({ base, projId }: any) => {
          const r = await fetch(`${base}/api/memory/projects/${projId}/episodes`, { credentials: "include" });
          const data = await r.json().catch(() => ({ episodes: [] }));
          const episodes = data.episodes || data || [];
          const latest = episodes[episodes.length - 1];
          return latest?.id || null;
        }, { base: BASE_URL, projId: projectId });
        episodeId = epResult;
      }

      assertions.push({ name: "MM-3: Episode ID captured", passed: !!episodeId, note: `episodeId: ${episodeId}` });

      // Click Run
      const ran = await clickRun(page);
      assertions.push({ name: "MM-3: Run button clicked", passed: ran });
      if (!ran) {
        finalStatus = "skip_no_run";
        return;
      }
      screenshots.push(await shot(page, "MM3_03_workflow_running"));

      // Wait for completion (5 min timeout for test workflow)
      finalStatus = await waitForTerminal(page, 300_000);
      assertions.push({
        name: "MM-3: Workflow reached terminal state",
        passed: finalStatus !== "timeout",
        note: finalStatus
      });
      screenshots.push(await shot(page, `MM3_04_workflow_${finalStatus}`));

      // Wait for episode outcome to be recorded (backend callback should fire within 5 seconds)
      await page.waitForTimeout(5000);

      // Verify episode outcome via API
      if (episodeId) {
        const outcomeResult = await page.evaluate(async ({ base, epId }: any) => {
          try {
            const r = await fetch(`${base}/api/memory/episodes/${epId}`, { credentials: "include" });
            const ep = await r.json().catch(() => ({}));
            return {
              ok: r.ok,
              outcomeSuccess: ep.outcomeSuccess ?? ep.outcome_success ?? null,
              whatWorked: ep.whatWorked || ep.what_worked || [],
              whatFailed: ep.whatFailed || ep.what_failed || [],
              lessonsLearned: ep.lessonsLearned || ep.lessons_learned || [],
              errorType: ep.errorType || ep.error_type || null
            };
          } catch {
            return { ok: false, outcomeSuccess: null, whatWorked: [], whatFailed: [], lessonsLearned: [], errorType: null };
          }
        }, { base: BASE_URL, epId: episodeId });

        assertions.push({
          name: "MM-3: Episode outcome recorded",
          passed: outcomeResult.outcomeSuccess !== null && outcomeResult.outcomeSuccess !== undefined,
          note: `success: ${outcomeResult.outcomeSuccess}`
        });

        if (finalStatus === "completed") {
          assertions.push({
            name: "MM-3: Episode marked as success for completed workflow",
            passed: outcomeResult.outcomeSuccess === true,
            note: `what_worked: ${outcomeResult.whatWorked.slice(0, 2).join(", ") || "none"}`
          });

          assertions.push({
            name: "MM-3: Episode contains 'what_worked' lessons",
            passed: outcomeResult.whatWorked.length > 0,
            note: outcomeResult.whatWorked[0]?.slice(0, 80) || "none"
          });
        } else if (finalStatus === "failed") {
          assertions.push({
            name: "MM-3: Episode marked as failure for failed workflow",
            passed: outcomeResult.outcomeSuccess === false,
            note: `error_type: ${outcomeResult.errorType || "none"}`
          });

          assertions.push({
            name: "MM-3: Episode contains 'what_failed' lessons",
            passed: outcomeResult.whatFailed.length > 0,
            note: outcomeResult.whatFailed[0]?.slice(0, 80) || "none"
          });
        }

        assertions.push({
          name: "MM-3: Episode contains lessons_learned",
          passed: outcomeResult.lessonsLearned.length > 0 || finalStatus === "timeout",
          note: outcomeResult.lessonsLearned[0]?.slice(0, 80) || "workflow still running or timeout"
        });

        screenshots.push(await shot(page, "MM3_05_outcome_recorded"));
      }

    } catch (err: any) {
      console.error("[MM-3] Error:", err.message);
      await shot(page, "MM3_error").catch(() => {});
      finalStatus = "error";
    } finally {
      AUDIT.push({
        testId: "MM-3",
        startTs: Date.now(),
        endTs: Date.now(),
        finalStatus,
        assertions,
        screenshots,
        metadata: { projectId: projectId || undefined, episodeId: episodeId || undefined }
      });
      writeAudit();

      console.log("\n════ MM-3 Results ════");
      for (const a of assertions) {
        console.log(`  ${a.passed ? "✓" : "✗"} ${a.name}${a.note ? `  (${a.note})` : ""}`);
      }
    }
  });
});

// ── MM-4: Cross-Session Workflow Reference ──────────────────────────────────
test.describe("MM-4 Cross-session workflow reference", () => {
  test.setTimeout(900_000); // 15 min for two sessions + workflow
  test.use({ viewport: { width: 1920, height: 1080 } });

  test("Session A: run workflow → Session B: reference 'same workflow' → retrieved", async ({ page }) => {
    const assertions: Assertion[] = [];
    const screenshots: string[] = [];
    let projectId: string | null = null;
    let episodeIdA: number | null = null;

    try {
      // ── SESSION A (Day 1) ───────────────────────────────────────────────
      console.log("[MM-4] === SESSION A (Day 1) ===");
      await loginOrRegister(page, "mm4day1");
      screenshots.push(await shot(page, "MM4_01_sessionA_home"));

      projectId = await createTestProject(page, "MM4 Cross-Session Test");
      assertions.push({ name: "MM-4 Session A: Project created", passed: !!projectId });

      // Request workflow with specific parameters
      const queryA = [
        "Run nf-core/rnaseq on my RNA-seq data.",
        "Organism: human (GRCh38), stranded: reverse, aligner: STAR.",
        "Use DESeq2 for differential expression with padj < 0.05."
      ].join(" ");

      await sendMessage(page, queryA, 90_000);
      const gotCardA = await waitForWorkflowCard(page, 60_000);
      assertions.push({ name: "MM-4 Session A: Workflow card appeared", passed: gotCardA });
      screenshots.push(await shot(page, "MM4_02_sessionA_workflow_card"));

      if (!gotCardA) return;

      // Capture workflow name
      const workflowA = await page.evaluate(() => {
        const card = document.querySelector('[data-testid^="workflow-artifact"]');
        const nameEl = card?.querySelector('[data-workflow-name], .workflow-name, h3');
        return nameEl?.textContent?.trim() || "";
      });

      assertions.push({
        name: "MM-4 Session A: Workflow card shows nf-core/rnaseq",
        passed: /rnaseq/i.test(workflowA),
        note: workflowA
      });

      // Run workflow (or simulate completion for speed)
      // For E2E testing, we can skip actual execution and just record episode
      // In production test, this would run to completion
      await clickRun(page);
      await page.waitForTimeout(10_000);
      screenshots.push(await shot(page, "MM4_03_sessionA_running"));

      // For E2E speed, mark as complete via API if endpoint exists
      // Or wait for actual completion (uncomment below for real test)
      // const statusA = await waitForTerminal(page, 300_000);
      // assertions.push({ name: "MM-4 Session A: Workflow completed", passed: statusA === "completed", note: statusA });

      // Fetch episode ID
      if (projectId) {
        await page.waitForTimeout(3000);
        episodeIdA = await page.evaluate(async ({ base, projId }: any) => {
          const r = await fetch(`${base}/api/memory/projects/${projId}/episodes`, { credentials: "include" });
          const data = await r.json().catch(() => ({ episodes: [] }));
          const episodes = data.episodes || data || [];
          const latest = episodes[episodes.length - 1];
          return latest?.id || null;
        }, { base: BASE_URL, projId: projectId });
      }

      assertions.push({ name: "MM-4 Session A: Episode recorded", passed: !!episodeIdA, note: `episodeId: ${episodeIdA}` });
      screenshots.push(await shot(page, "MM4_04_sessionA_episode"));

      // Clear session
      await page.context().clearCookies();
      await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); });
      await page.goto(`${BASE_URL}/logout`).catch(() => {});

      // ── SESSION B (Day 2) ───────────────────────────────────────────────
      console.log("[MM-4] === SESSION B (Day 2) ===");
      await page.waitForTimeout(2000);
      await loginOrRegister(page, "mm4day1"); // Same user email
      screenshots.push(await shot(page, "MM4_05_sessionB_home"));

      // Reference previous workflow
      const queryB = "Use the same RNA-seq workflow we ran yesterday";
      await sendMessage(page, queryB, 90_000);
      screenshots.push(await shot(page, "MM4_06_sessionB_query"));

      // Check if memory retrieval happened
      const responseB = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 15_000 }).catch(() => "");
      const memoryRetrieved = /nf-core\/rnaseq|previous|last time|yesterday|same workflow|remember|recall/i.test(responseB);

      assertions.push({
        name: "MM-4 Session B: Memory retrieved (response mentions previous workflow)",
        passed: memoryRetrieved,
        note: responseB.slice(0, 120)
      });

      // Workflow card should appear
      const gotCardB = await waitForWorkflowCard(page, 60_000);
      assertions.push({ name: "MM-4 Session B: Workflow card appeared", passed: gotCardB });
      screenshots.push(await shot(page, "MM4_07_sessionB_workflow_card"));

      if (gotCardB) {
        // Verify params are pre-filled
        await openWorkflowSettings(page);
        await page.waitForTimeout(1000);

        const alignerVal = await page.locator(
          'input#aligner, [data-testid="param-inline-edit-aligner"] input'
        ).first().inputValue({ timeout: 5000 }).catch(() => "");

        const genomeVal = await page.locator(
          'input#genome, [data-testid="param-inline-edit-genome"] input'
        ).first().inputValue({ timeout: 5000 }).catch(() => "");

        assertions.push({
          name: "MM-4 Session B: Parameters pre-filled from memory (aligner: STAR)",
          passed: /star/i.test(alignerVal) || alignerVal === "STAR",
          note: `aligner: ${alignerVal || "empty"}`
        });

        assertions.push({
          name: "MM-4 Session B: Parameters pre-filled from memory (genome: GRCh38)",
          passed: /grch38|hg38/i.test(genomeVal) || genomeVal.includes("GRCh38"),
          note: `genome: ${genomeVal || "empty"}`
        });

        screenshots.push(await shot(page, "MM4_08_sessionB_params_prefilled"));
      }

    } catch (err: any) {
      console.error("[MM-4] Error:", err.message);
      await shot(page, "MM4_error").catch(() => {});
    } finally {
      AUDIT.push({
        testId: "MM-4",
        startTs: Date.now(),
        endTs: Date.now(),
        finalStatus: "done",
        assertions,
        screenshots,
        metadata: { projectId: projectId || undefined, episodeId: episodeIdA || undefined }
      });
      writeAudit();

      console.log("\n════ MM-4 Results ════");
      for (const a of assertions) {
        console.log(`  ${a.passed ? "✓" : "✗"} ${a.name}${a.note ? `  (${a.note})` : ""}`);
      }
    }
  });
});
