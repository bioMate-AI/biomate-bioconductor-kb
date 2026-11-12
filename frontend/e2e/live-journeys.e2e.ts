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
 * Order: d → a → e → b+c, each an independent test; (e) and (b+c) need the
 * file (a) uploads and skip with a reason if it is missing (a SKIP is NOT
 * green — scripts/run_live_journeys.sh counts it as a failure).
 *
 * Rules (CLAUDE.md §Testing Rules / §E2E plan discipline):
 *  - NO route mocking (no page.route / msw / stubs) — anywhere in this file.
 *  - ONE login per harness (the canonical fixture lifeifei163361@163.com),
 *    ONE project per harness — both in globalSetup (live-journeys.global.ts),
 *    project deleted in globalTeardown. Never /api/auth/register.
 *  - (b) chats over the dataset that (a) uploaded; (c) reloads the chat (b)
 *    produced (one test, two steps).
 *  - LLM path budget: 120 s for the direct-compute answer.
 *
 * Run: scripts/run_live_journeys.sh   (or: npx playwright test -c playwright.live.config.ts)
 * Env: BIOMATE_URL (default https://dev-public.biomate.ai),
 *      E2E_FIXTURE_PASSWORD (else ~/.config/biomate/e2e_fixture_password),
 *      E2E_TEST_TOKEN (default biomate-e2e-bypass-token-dev-only).
 */
import { test, expect, request as pwRequest, type APIRequestContext, type BrowserContext, type Page } from '@playwright/test';
import { readFileSync, mkdirSync, writeFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { STATE_FILE } from './live-journeys.global';

const HERE = path.dirname(fileURLToPath(import.meta.url));

const BASE = (process.env.BIOMATE_URL || 'https://dev-public.biomate.ai').replace(/\/$/, '');
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


const fixtureLines = readFileSync(FIXTURE, 'utf8').split('\n').filter((l) => l.trim().length > 0);
const FIXTURE_ROWS = fixtureLines.length; // 200
const FIXTURE_COLUMNS = Object.keys(JSON.parse(fixtureLines[0])); // source, drug, page, headers, rows

// ── Shared harness state (one login, one project — from globalSetup) ─────────
// Journeys are independent tests (default mode): a failure in one does not
// skip the others. Cross-journey state (the uploaded file) goes through the
// state file because Playwright restarts the worker after a failure.
// Read lazily (in beforeAll): test files are also loaded for listing, which
// can happen before globalSetup has written the state file.
let token = '';
let projectId = '';
const saveState = (patch: Record<string, string>) => {
  const cur = JSON.parse(readFileSync(STATE_FILE, 'utf8'));
  writeFileSync(STATE_FILE, JSON.stringify({ ...cur, ...patch }, null, 2));
};
const currentFileId = (): string => JSON.parse(readFileSync(STATE_FILE, 'utf8')).fileId || '';
let api: APIRequestContext;
let ctx: BrowserContext;
let page: Page;
let chatSessionUrl = '';
const consoleErrors: string[] = [];

async function shot(name: string) {
  mkdirSync(SHOTS, { recursive: true });
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: false }).catch(() => {});
}

test.beforeAll(async ({ browser }) => {
  const state = JSON.parse(readFileSync(STATE_FILE, 'utf8')) as { token: string; projectId: string };
  token = state.token;
  projectId = state.projectId;
  // No login here — globalSetup did it once. Just an API context + a browser
  // context carrying the cookie (re-created if Playwright restarts the worker).
  api = await pwRequest.newContext({
    baseURL: BASE,
    timeout: 90_000,
    extraHTTPHeaders: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
  });
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
  writeFileSync(path.join(SHOTS, `console-errors-${process.pid}.txt`), consoleErrors.join('\n'));
  await ctx?.close().catch(() => {});
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
    // Tolerate a transient network blip on a poll; the run itself is server-side.
    res = await api.get(`/api/inference/${runId}/result`).then((x) => x.json()).catch(() => ({ status: 'running' }));
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
  // Models panel (2026-11-11): tabs 训练 / 模型库 / 分子学习 — "run a model" lives in 模型库.
  const runTab = page.getByRole('tab', { name: /模型库|Model library|Run a model|运行模型/ });
  if (await runTab.first().isVisible().catch(() => false)) {
    await runTab.first().click();
    await page.locator('[data-testid="domain-structure"]').click().catch(() => {});
    const box = page.locator('[data-testid="run-pretrained-input"]').or(page.getByRole('textbox')).first();
    await box.fill(PROTEIN);
    // Capture the result the PAGE received: a "completed" badge alone is not an
    // outcome (2026-11-10: the UI showed "completed" with a 1-point pLDDT).
    const uiResult = page.waitForResponse(async (res) => {
      if (!/\/api\/inference\/[^/]+\/result/.test(res.url())) return false;
      const j = await res.json().catch(() => ({}));
      return j.status === 'completed' || j.status === 'failed';
    }, { timeout: 300_000 }).then((r) => r.json()).catch(() => null);
    await page.locator('[data-testid="run-pretrained-submit"]').or(page.getByRole('button', { name: /Run inference|运行推理/ })).first().click();
    await shot('d1_models_running');
    const done = page.locator('[data-testid="result-status-completed"]').or(page.getByText(/^completed$|已完成/));
    const failed = page.locator('[data-testid="result-status-failed"], [data-testid="result-error"]');
    await expect(done.or(failed).first()).toBeVisible({ timeout: 300_000 });
    await shot('d2_models_result');
    expect(await failed.count(), `UI inference failed: ${await failed.allInnerTexts()}`).toBe(0);
    const ui = await uiResult;
    expect(ui, 'the page never received a terminal inference result').toBeTruthy();
    expect(ui.status, `UI inference: ${ui.error ?? ''}`).toBe('completed');
    expect(Array.isArray(ui.plddt) ? ui.plddt.length : -1, `UI-run Boltz-2 pLDDT is not per-residue (got ${JSON.stringify(ui.plddt).slice(0, 80)})`).toBe(PROTEIN.length);
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
  const fileId = file.id as string;
  saveState({ fileId });
  expect(file.content_type).toBe('application/x-ndjson');

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
  // The table is windowed (only visible rows are rendered, more load on scroll), so
  // "the last DOM row is in view" is not meaningful. The outcome is: after scrolling,
  // the rows the user SEES are later records than before.
  const visibleFirstCell = () => scroller.evaluate((el) => {
    const box = el.getBoundingClientRect();
    const row = Array.from(el.querySelectorAll('tbody tr')).find((r) => {
      const b = (r as HTMLElement).getBoundingClientRect();
      return b.bottom > box.top + 1 && b.top < box.bottom - 1;
    });
    return row ? (row.textContent || '').trim().slice(0, 120) : '';
  });
  await scroller.evaluate((el) => { el.scrollTop = 0; });
  await page.waitForTimeout(300);
  const topRow = await visibleFirstCell();
  await scroller.evaluate((el) => { el.scrollTop = el.scrollHeight; });
  await page.waitForTimeout(800);
  const bottomRow = await visibleFirstCell();
  expect(topRow, 'no row visible at the top of the preview').not.toBe('');
  expect(bottomRow, 'no row visible after scrolling').not.toBe('');
  expect(bottomRow, 'scrolling did not reveal later records').not.toBe(topRow);
  await shot('a2_dataset_preview_scrolled');
});

// ── (b)+(c) Chat direct compute, then refresh keeps the chat ────────────────
// One test with two steps: (c) needs the chat (b) creates, so a purely
// presentational (soft) failure in (b) must not stop (c) from running.
// Hard assertions = the functional contract; expect.soft = user-visible polish
// that must still be fixed (it fails the run) but must not hide step (c).
test('b+c. chat: "不用工作流" computes directly with the true count; refresh keeps the chat', async () => {
  const fileId = currentFileId();
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

// ── (e) Training from the panel → a REAL training run completes on Batch ────
// Same two calls the 训练 tab's 开始训练 button makes (models-api.ts launchTraining):
// POST /api/model-training/plan, then POST /api/workflows/execute; then the run must
// reach `completed` (not merely be accepted) and appear in the panel's run list.
test('e. training: a tabular classifier trains to completion from the panel path', async () => {
  test.setTimeout(45 * 60_000);

  // e0. A table too small to train on is refused BEFORE a Batch job is spent
  // (dev run c0d27792: a 1-row contrasts.csv crashed 5-fold CV on Batch).
  const tiny = await api.post(`/api/projects/${projectId}/files/upload`, {
    multipart: { file: { name: 'one_row.csv', mimeType: 'text/csv',
      buffer: Buffer.from('id,variable,reference,target\nA_vs_B,condition,B,A\n') } },
  });
  expect(tiny.status(), `tiny upload: ${(await tiny.text()).slice(0, 200)}`).toBeLessThan(400);
  const tinyId = ((await tiny.json()).file || {}).id;
  const refused = await api.post('/api/model-training/plan', {
    data: { projectId, fileId: tinyId, model_type: 'sklearn_tabular', task_type: 'classification',
            target_col: 'variable', metric: 'accuracy' },
  });
  expect(refused.status(), 'a 1-row table must be refused at plan time').toBe(400);
  expect(String((await refused.json().catch(() => ({}))).error), 'refusal must carry the localisable code').toMatch(/^dataset_too_small:1:/);

  const csv = path.join(HERE, 'fixtures', 'train_tabular.csv');
  const up = await api.post(`/api/projects/${projectId}/files/upload`, {
    multipart: { file: { name: 'train_tabular.csv', mimeType: 'text/csv', buffer: readFileSync(csv) } },
  });
  expect(up.status(), `upload: ${(await up.text()).slice(0, 200)}`).toBeLessThan(400);
  const fileId = ((await up.json()).file || {}).id;
  expect(fileId, 'upload returned no file id').toBeTruthy();

  const planRes = await api.post('/api/model-training/plan', {
    data: { projectId, fileId, model_type: 'sklearn_tabular', task_type: 'classification',
            target_col: 'label', metric: 'accuracy', gate_threshold: 0.6, model_name: 'live-journey-tabular' },
  });
  const plan = await planRes.json().catch(() => ({}));
  expect(planRes.status(), `plan: ${JSON.stringify(plan).slice(0, 300)}`).toBe(200);
  expect(plan.workflow_ga?.name, 'plan has no workflow').toBeTruthy();

  const exec = await api.post('/api/workflows/execute', {
    data: { workflowDefinition: plan.workflow_ga, workflowName: plan.workflow_ga.name,
            executionConfig: { mode: 'production', executionEngine: 'nextflow', computeConfig: plan.compute_config },
            inputs: [], projectId },
  });
  const ex = await exec.json().catch(() => ({}));
  expect(exec.status(), `execute: ${JSON.stringify(ex).slice(0, 300)}`).toBeLessThan(400);
  const runId = ex.runId;
  expect(runId, 'execute returned no runId').toBeTruthy();
  test.info().annotations.push({ type: 'training-run', description: String(runId) });

  let last: any = {};
  const deadline = Date.now() + 40 * 60_000;
  while (Date.now() < deadline) {
    const st = await api.get(`/api/workflows/runs/${encodeURIComponent(runId)}/status`);
    last = await st.json().catch(() => ({}));
    if (['completed', 'failed', 'cancelled', 'error'].includes(String(last.status))) break;
    await new Promise((r) => setTimeout(r, 15_000));
  }
  expect(last.status, `training run ${runId} ended ${last.status}: ${last.errorMessage ?? ''}`).toBe('completed');

  // The panel lists it WITH its result: the score read from the run's own
  // metrics.json and the quality-gate verdict (was 'Not recorded' until 2026-11-11).
  const act = await api.get(`/api/model-tracks/train?project=${encodeURIComponent(projectId)}`);
  const rows: any[] = (await act.json().catch(() => ({}))).runs || [];
  const row = rows.find((r) => r.name === 'live-journey-tabular' && r.status === 'completed');
  expect(row, `no completed live-journey-tabular row: ${JSON.stringify(rows).slice(0, 300)}`).toBeTruthy();
  expect(row.metricName, `score not recorded: ${JSON.stringify(row)}`).toBe('accuracy');
  expect(row.metricValue).toBeGreaterThanOrEqual(0.6);
  expect(row.gateStatus).toBe('pass');
  await page.goto(`${BASE}/models`, { waitUntil: 'domcontentloaded' });
  await expect(page.getByText('live-journey-tabular').first(), 'trained run missing from 训练运行').toBeVisible({ timeout: 60_000 });
  await expect(page.getByText(/(?:准确率|Accuracy) 0\.\d{3}/).first(), 'score not shown in 训练运行').toBeVisible({ timeout: 30_000 });
  await shot('e1_training_completed');
});
