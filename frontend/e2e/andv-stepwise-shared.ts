/**
 * Shared helpers for Plan A / ANDV inhibitor stepwise E2E suites.
 * No page.route() mocking — live BioMate stack only.
 */
import { Page, expect } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  sendChatMessage,
  waitForResponseComplete,
} from "./helpers.js";

export {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  sendChatMessage,
  waitForResponseComplete,
};

export interface SuiteAssertion {
  name: string;
  passed: boolean;
  note?: string;
}

export interface StepwiseSuiteRecord {
  testId: string;
  runId: string | null;
  startTs: number;
  endTs: number;
  finalStatus: "completed" | "failed" | "skipped" | "timeout" | "unknown";
  assertions: SuiteAssertion[];
  screenshots: string[];
  notes: string[];
  error?: string;
}

export function ensureScreenshotDir(dir: string): void {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

export async function shot(page: Page, dir: string, name: string): Promise<string> {
  const file = path.join(dir, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`[screenshot] ${file}`);
  return file;
}

export interface ChainedManifestStep {
  key: string;
  title: string;
  runId: string | null;
  status: string;
  panelTitle?: string;
  notes?: string[];
}

export interface ChainedPipelineManifest {
  created_at: string;
  source: "biomate_ui_e2e";
  steps: ChainedManifestStep[];
}

export function readChainedManifest(manifestPath: string): ChainedManifestStep[] {
  if (!fs.existsSync(manifestPath)) return [];
  try {
    const data = JSON.parse(fs.readFileSync(manifestPath, "utf8")) as ChainedPipelineManifest;
    return Array.isArray(data.steps) ? data.steps : [];
  } catch {
    return [];
  }
}

/** Merge one step into an on-disk manifest (supports --grep INH-C4 isolated runs). */
export function mergeChainedStepIntoManifest(
  manifestPath: string,
  step: ChainedManifestStep
): ChainedManifestStep[] {
  const steps = readChainedManifest(manifestPath).filter((s) => s.key !== step.key);
  steps.push(step);
  return steps;
}

export function writeChainedManifest(
  manifestPath: string,
  steps: ChainedManifestStep[]
): void {
  const payload: ChainedPipelineManifest = {
    created_at: new Date().toISOString(),
    source: "biomate_ui_e2e",
    steps,
  };
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  fs.writeFileSync(manifestPath, JSON.stringify(payload, null, 2));
  console.log(`[audit] wrote chained manifest ${manifestPath} (${steps.length} steps)`);
}

export async function getWorkflowPanelTitle(page: Page): Promise<string> {
  return (
    (await page
      .locator(
        '[data-testid="workflow-artifact-panel"] .panel-name, [data-testid="workflow-right-panel"] .panel-name'
      )
      .first()
      .textContent({ timeout: 5000 })
      .catch(() => "")) ?? ""
  ).trim();
}

/** True when the right panel shows codon optimization (not epitope/mhcquant). */
export function isCodonOptimizationPanelTitle(panelTitle: string): boolean {
  const title = panelTitle.trim();
  if (!title) return false;
  if (/codon|optimize|heterologous/i.test(title)) return true;
  if (/epitopeprediction|mhcquant/i.test(title)) return false;
  return false;
}

export async function assertCodonWorkflowPanelOrSkip(
  page: Page,
  label: string
): Promise<boolean> {
  const panelTitle = await getWorkflowPanelTitle(page);
  if (!isCodonOptimizationPanelTitle(panelTitle)) {
    console.log(`[${label}] skip — wrong workflow in panel: ${panelTitle.trim()}`);
    return false;
  }
  return true;
}

/** Read existing suite audit JSON; returns [] if missing or invalid. */
export function readSuiteAudit(auditPath: string): StepwiseSuiteRecord[] {
  if (!fs.existsSync(auditPath)) return [];
  try {
    const parsed = JSON.parse(fs.readFileSync(auditPath, "utf8"));
    return Array.isArray(parsed) ? (parsed as StepwiseSuiteRecord[]) : [];
  } catch {
    return [];
  }
}

/** Merge audit records by testId; newer endTs wins so partial reruns accumulate. */
export function mergeSuiteAuditRecords(
  existing: StepwiseSuiteRecord[],
  incoming: StepwiseSuiteRecord[]
): StepwiseSuiteRecord[] {
  const byId = new Map<string, StepwiseSuiteRecord>();
  for (const record of existing) byId.set(record.testId, record);
  for (const record of incoming) {
    const prev = byId.get(record.testId);
    if (!prev || record.endTs >= prev.endTs) byId.set(record.testId, record);
  }
  return [...byId.values()].sort((a, b) =>
    a.testId.localeCompare(b.testId, undefined, { numeric: true })
  );
}

export function writeSuiteAudit(auditPath: string, records: StepwiseSuiteRecord[]): void {
  fs.mkdirSync(path.dirname(auditPath), { recursive: true });
  const merged = mergeSuiteAuditRecords(readSuiteAudit(auditPath), records);
  fs.writeFileSync(auditPath, JSON.stringify(merged, null, 2));
  console.log(
    `[audit] wrote ${auditPath} (${merged.length} records, ${records.length} from this run)`
  );
}

export function attachExecuteCapture(page: Page): {
  captured: { runId?: string; executeUrl?: string };
  detach: () => void;
} {
  const captured: { runId?: string; executeUrl?: string } = {};
  const onResponse = async (resp: import("@playwright/test").Response) => {
    const url = resp.url();
    if (
      !url.includes("/api/workflows/execute") &&
      !url.includes("/api/nextflow/execute")
    ) {
      return;
    }
    if (resp.request().method() !== "POST") return;
    try {
      const payload = await resp.json();
      captured.runId =
        payload?.run_id ||
        payload?.runId ||
        payload?.execution?.run?.id ||
        captured.runId;
      captured.executeUrl = url.split("?")[0];
    } catch {
      /* ignore */
    }
  };
  page.on("response", onResponse);
  return {
    captured,
    detach: () => page.removeListener("response", onResponse),
  };
}

async function isAssistantThinking(page: Page): Promise<boolean> {
  const thinkingSelectors = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
  ];
  for (const sel of thinkingSelectors) {
    if (await page.locator(sel).first().isVisible({ timeout: 200 }).catch(() => false)) {
      return true;
    }
  }
  return false;
}

async function stopStuckAssistantReply(page: Page, label: string): Promise<void> {
  const stopBtn = page.getByRole("button", { name: /stop reply/i }).first();
  if (await stopBtn.isVisible({ timeout: 500 }).catch(() => false)) {
    await stopBtn.click({ force: true }).catch(() => {});
    console.log(`[${label}] clicked Stop reply — assistant was stuck thinking`);
    await page.waitForTimeout(1500);
  }
}

export async function waitForWorkflowCard(
  page: Page,
  label: string,
  followUpTexts: string[],
  timeoutMs = 480_000
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  const followUpIntervalMs = 45_000;
  const thinkingStuckMs = 90_000;
  let followUpsSent = 0;
  let lastFollowUpTs = Date.now() - followUpIntervalMs;
  let thinkingSince: number | null = null;

  while (Date.now() < deadline) {
    await page
      .evaluate(() => {
        const c = document.querySelector('[data-testid="chat-messages"], main');
        if (c) c.scrollTop = c.scrollHeight;
      })
      .catch(() => {});

    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="workflow-run-controls"]',
      '[data-testid="qc-settings-section"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        console.log(`[${label}] card via ${sel}`);
        await page.waitForTimeout(800);
        return true;
      }
    }

    const genFailed = await page
      .getByText(/Workflow generation is currently unavailable/i)
      .first()
      .isVisible({ timeout: 200 })
      .catch(() => false);

    const busy = await isAssistantThinking(page);
    if (busy) {
      thinkingSince = thinkingSince ?? Date.now();
      if (Date.now() - thinkingSince >= thinkingStuckMs) {
        await stopStuckAssistantReply(page, label);
        thinkingSince = null;
      }
    } else {
      thinkingSince = null;
    }

    const thinkingStuck =
      thinkingSince !== null && Date.now() - thinkingSince >= thinkingStuckMs;

    if (
      Date.now() - lastFollowUpTs >= followUpIntervalMs &&
      followUpsSent < followUpTexts.length &&
      (!busy || genFailed || thinkingStuck)
    ) {
      const ta = page.getByTestId("chat-input");
      if (await ta.isVisible({ timeout: 1000 }).catch(() => false)) {
        const msg = followUpTexts[followUpsSent];
        console.log(`[${label}] follow-up #${followUpsSent + 1}: ${msg.slice(0, 72)}…`);
        await sendChatMessage(page, msg);
        await waitForResponseComplete(page, 120_000);
        followUpsSent++;
        lastFollowUpTs = Date.now();
        thinkingSince = null;
        continue;
      }
    }
    await page.waitForTimeout(1500);
  }
  return false;
}

function paramLocator(page: Page, paramId: string) {
  return page
    .locator(
      `#${paramId}, input[name="${paramId}"], textarea#${paramId}, textarea[name="${paramId}"]`
    )
    .first();
}

async function openAdvancedSettings(page: Page, label: string): Promise<void> {
  const toggle = page.getByTestId("button-toggle-advanced-settings").first();
  if (await toggle.isVisible({ timeout: 2000 }).catch(() => false)) {
    const stripOpen = await page
      .locator(".strip.open")
      .first()
      .isVisible({ timeout: 300 })
      .catch(() => false);
    if (!stripOpen) {
      await toggle.click({ force: true }).catch(() => {});
      await page.waitForTimeout(400);
      console.log(`[${label}] opened Advanced settings`);
    }
    await page
      .locator(".strip-body")
      .first()
      .waitFor({ state: "visible", timeout: 8000 })
      .catch(() => {});
  }
}

/** Expand ParameterGroup accordions inside Advanced settings (inputs are hidden when collapsed). */
async function openGlobalParameterGroups(page: Page, label: string): Promise<void> {
  const stripBody = page.locator(".strip-body").first();
  if (!(await stripBody.isVisible({ timeout: 2000 }).catch(() => false))) return;

  const triggers = stripBody.locator("button[data-radix-accordion-trigger]");
  const count = await triggers.count().catch(() => 0);
  for (let i = 0; i < count; i++) {
    const trigger = triggers.nth(i);
    const state = await trigger.getAttribute("data-state").catch(() => null);
    if (state === "closed") {
      await trigger.click({ force: true }).catch(() => {});
      await page.waitForTimeout(250);
      console.log(`[${label}] expanded parameter group accordion ${i + 1}/${count}`);
    }
  }
}

const PARAM_LABEL_PATTERNS: Record<string, RegExp> = {
  input: /^input$/i,
  outdir: /^outdir$/i,
  tools: /^tools$/i,
  genome_reference: /^genome\s*reference/i,
  reference_actives: /^reference\s*actives/i,
  compound_library: /^compound\s*library/i,
  pdb_input: /^pdb/i,
  target_sequence: /^target\s*sequence/i,
  host_codon_usage: /^host\s*codon/i,
  rna_sequence: /^rna\s*sequence/i,
};

async function openClosedAccordions(page: Page): Promise<void> {
  const closedAccordions = page.locator('[data-state="closed"][data-radix-accordion-item]');
  const closedCount = await closedAccordions.count().catch(() => 0);
  for (let ci = 0; ci < closedCount; ci++) {
    const trigger = closedAccordions
      .nth(ci)
      .locator("button[data-radix-accordion-trigger]")
      .first();
    if (await trigger.isVisible({ timeout: 300 }).catch(() => false)) {
      await trigger.click({ force: true }).catch(() => {});
      await page.waitForTimeout(200);
    }
  }
  if (closedCount > 0) await page.waitForTimeout(300);
}

async function setParamValue(page: Page, paramId: string, value: string): Promise<boolean> {
  return page.evaluate(
    ({ id, val }: { id: string; val: string }) => {
      const el =
        (document.getElementById(id) as HTMLInputElement | HTMLTextAreaElement | null) ??
        (document.querySelector(
          `input[name="${id}"], textarea[name="${id}"]`
        ) as HTMLInputElement | HTMLTextAreaElement | null);
      if (!el) return false;
      const proto =
        el instanceof HTMLTextAreaElement
          ? window.HTMLTextAreaElement.prototype
          : window.HTMLInputElement.prototype;
      const nativeSetter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
      nativeSetter?.call(el, val);
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
      return true;
    },
    { id: paramId, val: value }
  );
}

export async function readParamValues(
  page: Page,
  paramIds: string[]
): Promise<Record<string, string>> {
  return page.evaluate((ids) => {
    const out: Record<string, string> = {};
    for (const id of ids) {
      const el = document.getElementById(id) as HTMLInputElement | HTMLTextAreaElement | null;
      out[id] = el?.value ?? "";
    }
    return out;
  }, paramIds);
}

export async function fillRequiredParams(
  page: Page,
  label: string,
  paramMap: Record<string, string>
): Promise<void> {
  await openAdvancedSettings(page, label);
  await openGlobalParameterGroups(page, label);
  await openClosedAccordions(page);

  for (const [paramId, value] of Object.entries(paramMap)) {
    if (!value) continue;
    let input = paramLocator(page, paramId);
    if (!(await input.isVisible({ timeout: 800 }).catch(() => false))) {
      const pat = PARAM_LABEL_PATTERNS[paramId];
      if (pat) {
        const byLabel = page.getByRole("textbox", { name: pat }).first();
        if (await byLabel.isVisible({ timeout: 800 }).catch(() => false)) {
          input = byLabel;
        }
      }
    }
    if (!(await input.isVisible({ timeout: 800 }).catch(() => false))) {
      console.log(`[${label}] param ${paramId} not visible — skip`);
      continue;
    }
    const currentVal = await input.inputValue().catch(() => "");
    if (currentVal && currentVal !== "null" && currentVal === value) {
      console.log(`[${label}] param ${paramId} already set`);
      continue;
    }
    const filled = await setParamValue(page, paramId, value);
    if (filled) {
      console.log(`[${label}] filled ${paramId}="${value}"`);
    }
    await page.waitForTimeout(150);
  }

  await page.waitForTimeout(400);
}

export async function clickRunAndWaitTerminal(
  page: Page,
  timeoutMs = 720_000
): Promise<"completed" | "failed" | "timeout"> {
  const runBtn = page.getByTestId("button-run-workflow-panel").first();
  await expect(runBtn).toBeVisible({ timeout: 15_000 });
  await expect(runBtn).toBeEnabled({ timeout: 120_000 });
  await runBtn.click();

  const statusBadge = page.getByTestId("workflow-overall-status-badge");
  const badgeVisible = await statusBadge
    .isVisible({ timeout: 60_000 })
    .catch(() => false);

  const completed = page.locator(
    '[data-testid="workflow-overall-status-badge"][data-status="completed"]'
  );
  const failed = page.locator(
    '[data-testid="workflow-overall-status-badge"][data-status="failed"]'
  );
  const execFailedBanner = page.getByText("Execution failed", { exact: false }).first();

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await completed.isVisible().catch(() => false)) return "completed";
    if (await failed.isVisible().catch(() => false)) return "failed";
    if (await execFailedBanner.isVisible().catch(() => false)) return "failed";
    await page.waitForTimeout(3000);
  }

  if (!badgeVisible) {
    if (await execFailedBanner.isVisible().catch(() => false)) return "failed";
  }
  return "timeout";
}

export async function assertAssistantMentions(
  page: Page,
  keywords: string[]
): Promise<boolean> {
  const text =
    (await page
      .locator('[data-is-latest-assistant="true"]')
      .last()
      .textContent({ timeout: 5000 })
      .catch(() => "")) ?? "";
  const lower = text.toLowerCase();
  return keywords.some((k) => lower.includes(k.toLowerCase()));
}
