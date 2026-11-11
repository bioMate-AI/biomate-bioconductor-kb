/**
 * Live user journeys against a DEPLOYED BioMate stack (default: dev).
 *
 * Why this file exists: the vitest suite (2,600+ tests, ~half stubbing the
 * backend) stayed green while dev was broken for real users — dead Models
 * panel (every BioNeMo model 410), answer trapped inside the progress box,
 * JSONL shown as comma-split CSV, a workflow forced on "不用工作流". Every
 * journey below drives the real UI and the real backend and asserts the
 * BEHAVIOUR a user sees. See docs/20261110_LIVE_JOURNEY_TESTS_AND_CI.md.
 *
 * Order: d (independent) → a → e → b+c. Serial mode skips everything after a
 * failure, so independent journeys run first and only true dependants are lost.
 *
 * Rules (CLAUDE.md §Testing Rules / §E2E plan discipline):
 *  - NO route mocking (no page.route / msw / stubs) — anywhere in this file.
 *  - ONE login per harness (the canonical fixture lifeifei163361@163.com),
 *    ONE project per harness, deleted in afterAll. Never /api/auth/register.
 *  - Journeys run serially and share state: (b) chats over the dataset that
 *    (a) uploaded, (c) reloads the chat that (b) produced.
 *  - LLM path budget: 120 s for the direct-compute answer.
 *
 * Run: scripts/run_live_journeys.sh   (or: npx playwright test -c playwright.live.config.ts)
 * Env: BIOMATE_URL (default https://dev-public.biomate.ai),
 *      E2E_FIXTURE_PASSWORD (else ~/.config/biomate/e2e_fixture_password),
 *      E2E_TEST_TOKEN (default biomate-e2e-bypass-token-dev-only).
 */
import { test, expect, request as pwRequest, type APIRequestContext, type BrowserContext, type Page } from '@playwright/test';
import { readFileSync, mkdirSync, existsSync, writeFileSync } from 'fs';
import { homedir } from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

const BASE = (process.env.BIOMATE_URL || 'https://dev-public.biomate.ai').replace(/\/$/, '');
const EMAIL = 'lifeifei163361@163.com';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const FIXTURE = path.join(HERE, 'fixtures', 'epar_sample.jsonl');
const SHOTS = path.join(HERE, 'screenshots', 'live-journeys');
const QUESTION = '你可以直接编程统计吗 不用工作流';
const LLM_BUDGET_MS = 120_000;
// Short protein for Boltz-2 (33 aa → pLDDT array of length 33).
const PROTEIN = 'MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ';
const DNA = 'ACGTACGTAGCTAGCTAGCATCGATCG';
const EVO2_TOKENS = 20;

// Things that must never be on screen for a "不用工作流" direct-compute turn.
const WORKFLOW_UI = [
  '[data-testid="chat-message-workflow"]',
  '[data-testid^="workflow-artifact-anchor-"]',
  '.wf-chip',
  '.wf-panel',
  '[data-testid="workflow-panel"]',
].join(', ');

function fixturePassword(): string {
  if (process.env.E2E_FIXTURE_PASSWORD) return process.env.E2E_FIXTURE_PASSWORD;
  const f = path.join(homedir(), '.config', 'biomate', 'e2e_fixture_password');
  if (existsSync(f)) return readFileSync(f, 'utf8').trim();
  throw new Error('No fixture password: set E2E_FIXTURE_PASSWORD or create ~/.config/biomate/e2e_fixture_password');
}

const fixtureLines = readFileSync(FIXTURE, 'utf8').split('\n').filter((l) => l.trim().length > 0);
const FIXTURE_ROWS = fixtureLines.length; // 200
const FIXTURE_COLUMNS = Object.keys(JSON.parse(fixtureLines[0])); // source, drug, page, headers, rows

// ── Shared harness state (one login, one project) ────────────────────────────
let token = '';
let api: APIRequestContext;
let ctx: BrowserContext;
let page: Page;
let projectId = '';
let fileId = '';
let uploadContentType = '';
let chatSessionUrl = '';
const consoleErrors: string[] = [];

async function shot(name: string) {
  mkdirSync(SHOTS, { recursive: true });
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: false }).catch(() => {});
}

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ browser }) => {
  // 1. Login ONCE.
  const anon = await pwRequest.newContext({ baseURL: BASE, extraHTTPHeaders: { 'x-e2e-test-token': E2E_TOKEN } });
  const r = await anon.post('/api/auth/login', { data: { email: EMAIL, password: fixturePassword() } });
  const body = await r.json().catch(() => ({}));
  await anon.dispose();
  expect(r.ok(), `login failed ${r.status()}: ${JSON.stringify(body).slice(0, 200)}`).toBeTruthy();
  token = body.token || body.accessToken;
  expect(token, 'login returned no token').toBeTruthy();

  api = await pwRequest.newContext({
    baseURL: BASE,
    extraHTTPHeaders: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
  });

  // 2. ONE project per harness.
  const pr = await api.post('/api/projects', {
    data: { name: `live-journeys ${new Date().toISOString()} (auto-deleted)`, description: 'Track E live journey harness — deleted in teardown' },
  });
  expect(pr.status(), `create project: ${await pr.text()}`).toBe(201);
  projectId = (await pr.json()).project.id;

  // 3. Browser context: cookie auth + active project + zh UI.
  // No extraHTTPHeaders here: a custom header on every browser request turns
  // cross-origin font loads into CORS preflights that Google Fonts rejects.
  ctx = await browser.newContext({ locale: 'zh-CN', viewport: { width: 1600, height: 1000 } });
  const host = new URL(BASE).hostname;
  await ctx.addCookies([{ name: 'biomate_token', value: token, domain: host, path: '/', secure: BASE.startsWith('https'), sameSite: 'Lax' }]);
  await ctx.addInitScript(([pid]) => {
    try {
      localStorage.setItem('i18nextLng', 'zh');
      localStorage.setItem('biomate-active-project-id', pid);
    } catch { /* storage blocked — the URL ?project= still carries it */ }
  }, [projectId]);
  page = await ctx.newPage();
  page.on('pageerror', (e) => consoleErrors.push(`pageerror: ${String(e).slice(0, 300)}`));
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(`console: ${m.text().slice(0, 300)}`); });
});

test.afterAll(async () => {
  mkdirSync(SHOTS, { recursive: true });
  writeFileSync(path.join(SHOTS, 'console-errors.txt'), consoleErrors.join('\n'));
  await ctx?.close().catch(() => {});
  if (projectId && api) {
    const d = await api.delete(`/api/projects/${projectId}`).catch(() => null);
    if (!d || !d.ok()) console.warn(`[live-journeys] project ${projectId} NOT deleted (${d?.status()}) — remove it by hand`);
  }
  await api?.dispose().catch(() => {});
});

// ── (d) Run a model: Boltz-2 + Evo2-7B return real payloads ──────────────────
async function infer(modelId: string, inputs: Record<string, unknown>) {
  const r = await api.post(`/api/models/${encodeURIComponent(modelId)}/infer`, { data: { inputs }, timeout: 300_000 });
  const body = await r.json().catch(() => ({}));
  expect(r.ok(), `${modelId} infer ${r.status()}: ${JSON.stringify(body).slice(0, 300)}`).toBeTruthy();
  const runId = body.run_id;
  let res: any = {};
  for (let i = 0; i < 60; i++) {
    res = await (await api.get(`/api/inference/${runId}/result`)).json();
    if (res.status !== 'running') break;
    await new Promise((s) => setTimeout(s, 5000));
  }
  return res;
}

test('d. models: Boltz-2 folds a protein and Evo2-7B generates — real payloads', async () => {
  test.setTimeout(12 * 60_000);
  // API — the authoritative behaviour (works whatever the Models page layout is).
  const boltz = await infer('bionemo:boltz2', { sequence: PROTEIN });
  expect(boltz.status, `Boltz-2: ${boltz.error ?? ''}`).toBe('completed');
  expect(String(boltz.structureFileRef || ''), 'Boltz-2 structure ref').toMatch(/\.(cif|pdb)$/);
  expect(Array.isArray(boltz.plddt) ? boltz.plddt.length : -1, 'pLDDT must be per-residue').toBe(PROTEIN.length);

  const evo = await infer('bionemo:evo2_7b', { sequence: DNA, num_tokens: EVO2_TOKENS });
  expect(evo.status, `Evo2-7B: ${evo.error ?? ''}`).toBe('completed');
  const iv = evo.tracks?.[0]?.intervals?.[0];
  expect(iv, `Evo2-7B returned no generated region: ${JSON.stringify(evo).slice(0, 300)}`).toBeTruthy();
  expect(iv.start).toBe(DNA.length);
  expect(iv.end - iv.start, 'generated length').toBeGreaterThan(0);

  // UI — resilient to the Models page being rebuilt in parallel.
  await page.goto(`${BASE}/models`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(3000);
  const runTab = page.locator('[data-testid="models-track-3"]').or(page.getByRole('tab', { name: /Run a model|运行模型/ }));
  if (await runTab.first().isVisible().catch(() => false)) {
    await runTab.first().click();
    await page.locator('[data-testid="domain-structure"]').click().catch(() => {});
    const box = page.locator('[data-testid="run-pretrained-input"]').or(page.getByRole('textbox')).first();
    await box.fill(PROTEIN);
    await page.locator('[data-testid="run-pretrained-submit"]').or(page.getByRole('button', { name: /Run inference|运行推理/ })).first().click();
    await shot('d1_models_running');
    const done = page.locator('[data-testid="result-status-completed"]').or(page.getByText(/^completed$|已完成/));
    const failed = page.locator('[data-testid="result-status-failed"], [data-testid="result-error"]');
    await expect(done.or(failed).first()).toBeVisible({ timeout: 300_000 });
    await shot('d2_models_result');
    expect(await failed.count(), `UI inference failed: ${await failed.allInnerTexts()}`).toBe(0);
    test.info().annotations.push({ type: 'ui-path', description: 'Run-a-model tab drove a real Boltz-2 inference to completed' });
  } else {
    // The page is being restructured: still require that it renders the live catalog.
    await expect(page.getByText(/Boltz-2/).first(), 'Models page does not render the live catalog').toBeVisible({ timeout: 60_000 });
    await shot('d1_models_page');
    test.info().annotations.push({ type: 'ui-path', description: 'Run-a-model tab not found — asserted catalog render only' });
  }
});


// ── (a) Dataset: JSONL upload → data panel shows records, not CSV fragments ──
test('a. dataset: JSONL upload opens as 5-column records with scrollable preview', async () => {
  const up = await api.post(`/api/projects/${projectId}/files/upload`, {
    // The browser often sends no / a generic type for .jsonl — send octet-stream
    // so this proves the SERVER derives the type from the extension.
    multipart: { file: { name: 'epar_sample.jsonl', mimeType: 'application/octet-stream', buffer: readFileSync(FIXTURE) } },
  });
  expect(up.status(), `upload: ${await up.text()}`).toBe(201);
  const file = (await up.json()).file;
  fileId = file.id;
  uploadContentType = file.content_type;
  expect(uploadContentType).toBe('application/x-ndjson');

  await page.goto(`${BASE}/files?project=${projectId}&file=${fileId}`, { waitUntil: 'domcontentloaded' });
  const table = page.locator('[data-testid="dataset-preview-table"]');
  await expect(table, 'dataset preview table never rendered (profile failed or file not opened)').toBeVisible({ timeout: 90_000 });
  await shot('a1_dataset_preview');

  // Columns: exactly the JSONL record keys — not comma fragments of the raw line.
  const headers = (await table.locator('thead th').allInnerTexts()).map((h) => h.replace(/[▲▼]/g, '').trim());
  expect(headers).toEqual(FIXTURE_COLUMNS);
  expect(FIXTURE_COLUMNS).toEqual(['source', 'drug', 'page', 'headers', 'rows']);

  // Row count: the stat grid's first card is the measured row count.
  const statGrid = page.locator('[data-testid="dataset-stat-grid"]');
  const stats = await statGrid.locator(':scope > div').allInnerTexts();
  const rowsStat = stats[0]?.split('\n').pop()?.replace(/,/g, '').trim();
  const colsStat = stats[1]?.split('\n').pop()?.trim();
  expect(Number(rowsStat), `row stat card: ${JSON.stringify(stats)}`).toBe(FIXTURE_ROWS);
  expect(Number(colsStat)).toBe(5);
  expect(stats.join(' '), 'content type card').toContain('application/x-ndjson');

  // Preview goes beyond the old 8-row cap and the pane actually scrolls.
  const bodyRows = await table.locator('tbody tr').count();
  expect(bodyRows, 'preview rows').toBeGreaterThan(8);
  const scroller = table.locator('div.overflow-auto').first();
  const before = await scroller.evaluate((el) => ({ sh: el.scrollHeight, ch: el.clientHeight }));
  expect(before.sh, 'preview pane is not scrollable').toBeGreaterThan(before.ch);
  await scroller.evaluate((el) => { el.scrollTop = el.scrollHeight; });
  const after = await scroller.evaluate((el) => el.scrollTop);
  expect(after, 'preview pane did not scroll').toBeGreaterThan(0);
  await expect(table.locator('tbody tr').nth(bodyRows - 1)).toBeInViewport();
  await shot('a2_dataset_preview_scrolled');
});

// ── (e) Training from the panel (prepared; skipped until the route exists) ───
test('e. training: plan a tabular classifier from the data panel', async () => {
  const probe = await api.post('/api/model-training/plan', { data: {} });
  test.skip(probe.status() === 404, 'POST /api/model-training/plan is not deployed yet (404) — journey prepared, enable when it ships');
  test.skip(!fileId, 'journey (a) did not upload the dataset');
  // Route exists: it must accept a real plan request over the uploaded dataset.
  const r = await api.post('/api/model-training/plan', {
    data: { projectId, fileId, task: 'classification', target: 'source' },
  });
  const body = await r.json().catch(() => ({}));
  expect(r.status(), `plan: ${JSON.stringify(body).slice(0, 300)}`).toBeLessThan(400);
  expect(body, 'plan response is empty').not.toEqual({});
});

// ── (b)+(c) Chat direct compute, then refresh keeps the chat ────────────────
// One test with two steps: (c) needs the chat (b) creates, and serial mode would
// otherwise skip (c) whenever a purely presentational (soft) check in (b) fails.
// Hard assertions = the functional contract; expect.soft = user-visible polish
// that must still be fixed (it fails the run) but must not hide step (c).
test('b+c. chat: "不用工作流" computes directly with the true count; refresh keeps the chat', async () => {
  test.skip(!fileId, 'journey (a) did not upload the dataset');
  test.setTimeout(LLM_BUDGET_MS + 180_000);

  await test.step('b. "不用工作流" → run_code executes, no workflow, answer outside the progress log', async () => {
    const q = new URLSearchParams({ project: projectId, attachFile: fileId, draft: QUESTION });
    await page.goto(`${BASE}/?${q}`, { waitUntil: 'domcontentloaded' });
    const input = page.locator('[data-testid="chat-input"]');
    await expect(input).toBeVisible({ timeout: 60_000 });
    // The dataset must be attached (chip) before sending, or the turn has no data.
    await expect(page.locator('[data-testid="composer-dataset-ref"]').first(), 'attachFile did not attach the dataset chip').toBeVisible({ timeout: 30_000 });
    await expect(input).toHaveValue(QUESTION, { timeout: 15_000 });
    await shot('b1_draft_with_dataset');

    // Capture the real chat SSE stream: the run_code tool_event is the ground
    // truth that code executed (the rendered block is how the user sees it).
    const streams: string[] = [];
    const onResp = async (res: any) => {
      if (!res.url().includes('/api/chat/stream')) return;
      try { streams.push(await res.text()); } catch { /* aborted */ }
    };
    page.on('response', onResp);
    await page.locator('[data-testid="chat-send-button"]').click();
    const t0 = Date.now();

    const runCode = page.locator('[data-testid^="tool-block-run_code-"]');
    const countRe = new RegExp(`(^|[^\\d,.])${FIXTURE_ROWS}([^\\d]|$)`);
    // Latest assistant text EXCLUDING anything inside the progress log / tool blocks.
    const answerOutsideLog = () => page.evaluate(() => {
      const msgs = Array.from(document.querySelectorAll('[data-role="assistant"]'));
      const last = msgs[msgs.length - 1] as HTMLElement | undefined;
      if (!last) return '';
      const clone = last.cloneNode(true) as HTMLElement;
      clone.querySelectorAll('[role="log"], [data-testid^="tool-block-"]').forEach((n) => n.remove());
      return clone.innerText || '';
    });

    // Poll until the answer states the count AND has stopped changing (the
    // agent narrates "let me look at the file…" between tool calls, so a long
    // intermediate text is NOT a finished answer). Budget: 120 s.
    let answer = '';
    let previous = '';
    let finished = false;
    while (Date.now() - t0 < LLM_BUDGET_MS) {
      await page.waitForTimeout(4000);
      const streaming = await page.locator('[data-testid="chat-stop-button"]').isVisible().catch(() => false);
      answer = await answerOutsideLog();
      if (!streaming && countRe.test(answer) && answer === previous) { finished = true; break; }
      previous = answer;
    }
    await page.waitForTimeout(2000);
    await shot('b2_answer');
    page.off('response', onResp);
    const sse = streams.join('\n');
    const toolEvents = sse.split('\n\n').filter((e) => /^event:\s*tool_event/m.test(e));
    const sseRunCode = toolEvents.filter((e) => /"name"\s*:\s*"run_code"/.test(e));
    const logText = (await page.locator('[role="log"]').allInnerTexts()).join('\n');
    const composer = await input.inputValue().catch(() => '?');
    writeFileSync(path.join(SHOTS, 'b_answer_text.txt'),
      `URL after send: ${page.url()}\nCOMPOSER after send: ${composer}\n` +
      `SSE bytes: ${sse.length}; tool_events: ${toolEvents.length}; run_code tool_events: ${sseRunCode.length}; ` +
      `rendered run_code blocks: ${await runCode.count()}\n` +
      `SSE event names: ${[...new Set((sse.match(/^event:\s*\S+/gm) || []).map((x) => x.replace(/^event:\s*/, '')))].join(', ')}\n\n` +
      `ANSWER (outside log):\n${answer}\n\nPROGRESS LOG:\n${logText}\n`);
    writeFileSync(path.join(SHOTS, 'b_chat_stream.sse.txt'), sse);

    // Functional contract (hard).
    // run_code evidence = a tool_event in the captured SSE OR a rendered block.
    // (Playwright cannot always read a streamed fetch body, so the SSE capture
    // alone is not a reliable negative.)
    const renderedRunCode = await runCode.count();
    expect(sseRunCode.length + renderedRunCode, 'no run_code tool_event in the SSE and no run_code block rendered — the turn did not execute code').toBeGreaterThan(0);
    expect(await page.locator(WORKFLOW_UI).count(), 'a workflow card/chip/panel appeared on a "不用工作流" turn').toBe(0);
    expect(countRe.test(answer), `answer (outside the progress log) does not state the true record count ${FIXTURE_ROWS}: ${answer.slice(0, 400)}`).toBeTruthy();
    expect(finished, 'answer did not finish within the 120 s budget').toBeTruthy();
    await expect.poll(() => page.url(), { timeout: 15_000, message: 'URL never gained ?session=' }).toMatch(/[?&]session=/);
    chatSessionUrl = page.url();

    // User-visible presentation (soft — fails the run, does not hide step c).
    expect.soft(renderedRunCode, 'run_code executed (SSE tool_event) but no run_code tool block is rendered in the chat').toBeGreaterThan(0);
    expect.soft(composer, 'composer still holds the sent question after send').toBe('');
  });

  await test.step('c. refresh keeps the chat (?session= survives reload, question still visible)', async () => {
    expect(chatSessionUrl, 'step b produced no chat session URL').toBeTruthy();
    await page.reload({ waitUntil: 'domcontentloaded' });
    await expect(page.locator('[data-role="user"]').getByText(QUESTION).first(), 'question vanished after refresh').toBeVisible({ timeout: 60_000 });
    expect(new URL(page.url()).searchParams.get('session')).toBe(new URL(chatSessionUrl).searchParams.get('session'));
    await expect(page.locator('[data-role="assistant"]').getByText(new RegExp(`${FIXTURE_ROWS}`)).first(), 'answer vanished after refresh').toBeVisible({ timeout: 30_000 });
    await shot('c1_after_refresh');
  });
});
