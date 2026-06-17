/**
 * sge-tier0-audit.e2e.ts
 *
 * Records video + screenshots of the schema-grounded extraction Phase 1
 * deployment against dev-public.biomate.ai for self-audit.
 *
 * For each of the 5 tier-0 demos:
 *   1. Logs in as the shared fixture user
 *   2. Sends the query in chat
 *   3. Waits for the workflow card → opens panel
 *   4. Captures: chat reply, panel-open, params-prefilled, full-screen
 *
 * Uses the shared fixture per CLAUDE.md (lifeifei163361@163.com).
 *
 * Run:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=… \
 *   PW_OUTPUT_DIR=e2e/sge-audit-artifacts \
 *   npx playwright test e2e/sge-tier0-audit.e2e.ts \
 *     --headed=false --reporter=line
 */
import { test, expect, type Page } from "@playwright/test";

const BASE_URL = (process.env.BIOMATE_URL || "http://localhost:5000").replace(/\/+$/, "");
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

type DemoSpec = {
  id: string;
  workflow: string;
  query: string;
  expectKeys: Array<{ key: string; regex: RegExp }>;
};

const DEMOS: DemoSpec[] = [
  {
    id: "T01",
    workflow: "bispecific_format_triage",
    query: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
    expectKeys: [
      { key: "target_a", regex: /pd-?1/i },
      { key: "target_b", regex: /vegf/i },
      { key: "indication", regex: /nsclc/i },
    ],
  },
  {
    id: "T02",
    workflow: "in_vivo_cart_codesign",
    query: "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence",
    expectKeys: [
      { key: "car_target", regex: /cd19/i },
      { key: "indication", regex: /dlbcl/i },
      { key: "delivery_cell", regex: /^t.?cell$/i },
      { key: "persistence", regex: /transient/i },
    ],
  },
  {
    id: "T03",
    workflow: "in_vivo_base_edit_design",
    query: "Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia",
    expectKeys: [
      { key: "target_gene", regex: /pcsk9/i },
      { key: "indication", regex: /hyperchol/i },
    ],
  },
  {
    id: "T04",
    workflow: "glp1_modality_bakeoff",
    query: "Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy",
    expectKeys: [{ key: "indication", regex: /mash|nash/i }],
  },
  {
    id: "T05",
    workflow: "modality_triage",
    query: "Triage modalities for a BCMA oncology target — try all options",
    expectKeys: [
      { key: "target_gene", regex: /bcma/i },
      { key: "indication", regex: /onco/i },
    ],
  },
];

async function loginShared(page: Page): Promise<{ ok: boolean; token?: string; note?: string }> {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();

  // Try login first; register-then-login if login fails.
  const loginUrl = `${BASE_URL}/api/auth/login`;
  const tryLogin = await page.request.post(loginUrl, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  let token = "";
  if (tryLogin.ok()) {
    token = (await tryLogin.json())?.token || "";
  } else if (tryLogin.status() === 401 || tryLogin.status() === 404) {
    // Register, then re-login
    const reg = await page.request.post(`${BASE_URL}/api/auth/register`, {
      headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
      data: {
        fullName: "Tier0 SGE Audit",
        email: FIXTURE_EMAIL,
        password: FIXTURE_PASSWORD,
        termsAccepted: true,
        privacyAccepted: true,
      },
    });
    if (reg.ok()) {
      token = (await reg.json())?.token || "";
    }
  }
  if (!token) return { ok: false, note: `login status=${tryLogin.status()}` };
  const url = new URL(BASE_URL);
  await page.context().addCookies([{
    name: "biomate_token",
    value: token,
    domain: url.hostname,
    path: "/",
    httpOnly: true,
    secure: BASE_URL.startsWith("https"),
    sameSite: "Strict",
  }]);
  return { ok: true, token };
}

async function sendChatQuery(page: Page, query: string): Promise<void> {
  const input = page.locator('[data-testid="chat-input"], textarea[placeholder*="Ask"]').first();
  await input.waitFor({ state: "visible", timeout: 60_000 });
  await input.click();
  await input.fill(query);
  await page.keyboard.press("Enter");
}

async function waitForWorkflowCard(page: Page, workflowName: string, timeoutMs = 180_000): Promise<boolean> {
  try {
    await page.waitForFunction(
      ({ name }) => {
        const txt = document.body.innerText.toLowerCase();
        return txt.includes(name.toLowerCase());
      },
      { name: workflowName },
      { timeout: timeoutMs },
    );
    return true;
  } catch {
    return false;
  }
}

async function openWorkflowPanel(page: Page): Promise<boolean> {
  const candidates = [
    'button[data-testid^="button-run-workflow-panel"]',
    'button:has-text("Open in panel")',
    'button:has-text("View workflow")',
    '[data-testid="wf-chip"] button',
    '.wf-chip',
  ];
  for (const sel of candidates) {
    const el = page.locator(sel).first();
    if (await el.count()) {
      try {
        await el.click({ timeout: 5_000 });
        await page.waitForTimeout(800);
        return true;
      } catch {
        // try next
      }
    }
  }
  return false;
}

async function readPrefilledParams(page: Page): Promise<Record<string, string>> {
  return await page.evaluate(() => {
    const out: Record<string, string> = {};
    // Inputs in the workflow panel form.
    document.querySelectorAll<HTMLInputElement>('input[id]').forEach((el) => {
      const id = el.id;
      if (!id) return;
      // Strip common form id prefixes ("param-", "global-")
      const key = id.replace(/^(param-|global-|qc-)/i, "");
      if (el.value && el.value.trim()) out[key] = el.value;
    });
    // Selects.
    document.querySelectorAll<HTMLSelectElement>('select[id]').forEach((el) => {
      const id = el.id;
      const key = id.replace(/^(param-|global-)/i, "");
      if (el.value && el.value.trim()) out[key] = el.value;
    });
    return out;
  });
}

test.describe("Schema-grounded extraction — tier-0 audit", () => {
  test.describe.configure({ mode: "serial" });

  for (const spec of DEMOS) {
    test(`${spec.id} ${spec.workflow}`, async ({ page }, testInfo) => {
      const shotDir = testInfo.outputDir;
      console.log(`\n=== ${spec.id} ${spec.workflow} ===`);
      console.log(`Query: ${spec.query}`);

      const login = await loginShared(page);
      console.log(`login: ${login.ok ? "OK" : "FAIL " + (login.note ?? "")}`);
      expect(login.ok, "fixture login").toBeTruthy();

      await page.goto(BASE_URL + "/", { waitUntil: "networkidle" });
      await page.screenshot({ path: `${shotDir}/01-home.png`, fullPage: true });

      await sendChatQuery(page, spec.query);
      await page.waitForTimeout(2_000);
      await page.screenshot({ path: `${shotDir}/02-sent.png`, fullPage: true });

      const cardOk = await waitForWorkflowCard(page, spec.workflow);
      console.log(`workflow card visible: ${cardOk}`);
      await page.screenshot({ path: `${shotDir}/03-card.png`, fullPage: true });

      if (cardOk) await openWorkflowPanel(page);
      await page.waitForTimeout(3_000);
      await page.screenshot({ path: `${shotDir}/04-panel.png`, fullPage: true });

      const prefilled = await readPrefilledParams(page);
      console.log("prefilled keys:", Object.keys(prefilled));
      console.log("prefilled:", JSON.stringify(prefilled));

      const expectations: Array<{ key: string; regex: string; got: string | undefined; pass: boolean }> = [];
      let allOk = true;
      for (const exp of spec.expectKeys) {
        const v = prefilled[exp.key];
        const ok = typeof v === "string" && exp.regex.test(v);
        expectations.push({ key: exp.key, regex: String(exp.regex), got: v, pass: ok });
        if (!ok) allOk = false;
      }
      console.log("expectations:", JSON.stringify(expectations, null, 2));
      await page.screenshot({ path: `${shotDir}/05-final.png`, fullPage: true });

      testInfo.attachments.push({
        name: `${spec.id}-prefill-audit.json`,
        contentType: "application/json",
        body: Buffer.from(JSON.stringify({ spec, prefilled, expectations, cardOk, allOk }, null, 2)),
      });

      expect(cardOk, `workflow card for ${spec.workflow}`).toBeTruthy();
      for (const e of expectations) {
        expect(e.pass, `${spec.id}.${e.key} expected ${e.regex} got "${e.got}"`).toBeTruthy();
      }
    });
  }
});
