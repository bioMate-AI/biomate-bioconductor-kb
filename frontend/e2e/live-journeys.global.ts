/**
 * Global setup / teardown for e2e/live-journeys.e2e.ts.
 *
 * Login ONCE and create ONE project per harness run (CLAUDE.md §E2E plan
 * discipline). Done here — not in a file-level beforeAll — so a failing
 * journey does not take the others down with it: Playwright restarts the
 * worker after a failure, which would re-run a beforeAll (second login, second
 * project). State is handed to the spec through a JSON file; teardown deletes
 * the project and the file.
 */
import { request } from '@playwright/test';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'fs';
import { homedir } from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import { resolveE2eBaseUrl } from "./_e2e-base-url";
const BASE = resolveE2eBaseUrl("https://dev-public.biomate.ai");

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const STATE_FILE = process.env.LIVE_JOURNEYS_STATE || path.join(HERE, '.live-journeys-state.json')  // NOT under test-results/: Playwright clears that dir at run start;

const EMAIL = 'lifeifei163361@163.com';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';

function fixturePassword(): string {
  if (process.env.E2E_FIXTURE_PASSWORD) return process.env.E2E_FIXTURE_PASSWORD;
  const f = path.join(homedir(), '.config', 'biomate', 'e2e_fixture_password');
  if (existsSync(f)) return readFileSync(f, 'utf8').trim();
  throw new Error('No fixture password: set E2E_FIXTURE_PASSWORD or create ~/.config/biomate/e2e_fixture_password');
}

async function withRetry<T>(what: string, fn: () => Promise<T>, tries = 3): Promise<T> {
  let last: unknown;
  for (let i = 0; i < tries; i++) {
    try { return await fn(); } catch (e) { last = e; await new Promise((r) => setTimeout(r, 5000)); }
  }
  throw new Error(`${what} failed after ${tries} attempts (network to ${BASE}?): ${String(last).slice(0, 300)}`);
}

export async function globalSetup() {
  const anon = await request.newContext({ baseURL: BASE, extraHTTPHeaders: { 'x-e2e-test-token': E2E_TOKEN }, timeout: 60_000 });
  const r = await withRetry('login', () => anon.post('/api/auth/login', { data: { email: EMAIL, password: fixturePassword() } }));
  const body = await r.json().catch(() => ({}));
  await anon.dispose();
  const token = body.token || body.accessToken;
  if (!r.ok() || !token) throw new Error(`login failed ${r.status()}: ${JSON.stringify(body).slice(0, 200)}`);

  const api = await request.newContext({ baseURL: BASE, extraHTTPHeaders: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN }, timeout: 60_000 });
  const pr = await withRetry('create project', () => api.post('/api/projects', {
    data: { name: `live-journeys ${new Date().toISOString()} (auto-deleted)`, description: 'Track E live journey harness — deleted in teardown' },
  }));
  if (pr.status() !== 201) throw new Error(`create project ${pr.status()}: ${await pr.text()}`);
  const projectId = (await pr.json()).project.id;
  await api.dispose();

  mkdirSync(path.dirname(STATE_FILE), { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify({ token, projectId }, null, 2));
}

export async function globalTeardown() {
  if (!existsSync(STATE_FILE)) return;
  const { token, projectId } = JSON.parse(readFileSync(STATE_FILE, 'utf8'));
  if (projectId) {
    const api = await request.newContext({ baseURL: BASE, extraHTTPHeaders: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN }, timeout: 60_000 });
    const d = await withRetry('delete project', () => api.delete(`/api/projects/${projectId}`)).catch((e) => { console.warn(String(e)); return null; });
    if (!d || !d.ok()) console.warn(`[live-journeys] project ${projectId} NOT deleted (${d?.status()}) — delete it by hand`);
    await api.dispose();
  }
  rmSync(STATE_FILE, { force: true });
}
