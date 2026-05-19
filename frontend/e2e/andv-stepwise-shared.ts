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

export function writeSuiteAudit(auditPath: string, records: StepwiseSuiteRecord[]): void {
  fs.writeFileSync(auditPath, JSON.stringify(records, null, 2));
  console.log(`[audit] wrote ${auditPath} (${records.length} records)`);
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

export async function waitForWorkflowCard(
  page: Page,
  label: string,
  followUpTexts: string[],
  timeoutMs = 300_000
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  const followUpIntervalMs = 45_000;
  let followUpsSent = 0;
  let lastFollowUpTs = Date.now();

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

    if (
      Date.now() - lastFollowUpTs >= followUpIntervalMs &&
      followUpsSent < followUpTexts.length
    ) {
      const thinking = ["[data-testid='chat-response-pending']"];
      const busy = await page
        .locator(thinking[0])
        .first()
        .isVisible({ timeout: 200 })
        .catch(() => false);
      if (!busy) {
        const ta = page.getByTestId("chat-input");
        if (await ta.isVisible({ timeout: 1000 }).catch(() => false)) {
          const msg = followUpTexts[followUpsSent];
          console.log(`[${label}] follow-up #${followUpsSent + 1}: ${msg.slice(0, 72)}…`);
          await sendChatMessage(page, msg);
          await waitForResponseComplete(page, 180_000);
          followUpsSent++;
          lastFollowUpTs = Date.now();
          continue;
        }
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
    if (currentVal && currentVal !== "null") {
      console.log(`[${label}] param ${paramId} already="${currentVal}"`);
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
