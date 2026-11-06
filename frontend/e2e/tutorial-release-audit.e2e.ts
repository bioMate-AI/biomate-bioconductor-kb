/** Read-only release evidence. No mocks, workflow launches, or overwritten captures. */
import { test, expect, request } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { loginAsFixture, BASE_URL } from './_fixture-login';

test.use({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 2 });
test('tutorial pilot: real session, downloadable results, and provenance', async ({ page }) => {
  test.setTimeout(240_000);
  const dir = path.resolve('../docs/qa/20261003-tutorial-release');
  fs.mkdirSync(dir, { recursive: true });
  const run = 'c40459b2-4dd0-407e-bbbd-e985df4ce0fc';
  const evidence: any = { checkedAt: new Date().toISOString(), baseUrl: BASE_URL, run, checks: [] };
  const failures: string[] = [];
  const check = async (name: string, fn: () => Promise<any>) => {
    try { const detail = await fn(); evidence.checks.push({ name, passed: true, detail }); }
    catch (e: any) { failures.push(name); evidence.checks.push({ name, passed: false, error: String(e.message).slice(0, 700) }); }
    fs.writeFileSync(path.join(dir, 'live-audit.json'), JSON.stringify(evidence, null, 2));
  };
  await loginAsFixture(page);
  await check('existing run is completed', async () => {
    const r = await page.request.get(`${BASE_URL}/api/workflows/runs/${run}`, { timeout: 30000 });
    expect(r.status()).toBe(200);
    const j = await r.json();
    fs.writeFileSync(path.join(dir, 'run-shape.json'), JSON.stringify({ keys: Object.keys(j), status: j.status, executionStatus: j.execution?.status, workflowName: j.workflowName }, null, 2));
    expect(['completed', 'succeeded', 'success']).toContain(String(j.execution?.status ?? j.status).toLowerCase());
    return { status: j.execution?.status ?? j.status, workflowName: j.workflowName };
  });
  await check('canonical output list contains results', async () => {
    const r = await page.request.get(`${BASE_URL}/api/runs/${run}/outputs`, { timeout: 45000 });
    expect(r.status()).toBe(200);
    const j = await r.json();
    const outputs = j.outputs || [];
    fs.writeFileSync(path.join(dir, 'output-inventory.json'), JSON.stringify(outputs.map((o: any) => ({ name: o.name, size: o.size, mimeType: o.mimeType, fields: Object.keys(o) })), null, 2));
    expect(outputs.length).toBeGreaterThan(0);
    for (const o of outputs) {
      if (o.size > 100000 || !/\.(json|txt|yml)$/.test(o.name)) continue;
      const redirect = await page.request.get(`${BASE_URL}/api/runs/${run}/output/${encodeURIComponent(o.name)}`, { timeout: 30000, maxRedirects: 0 });
      // Never forward the BioMate Authorization header to object storage.
      const external = await request.newContext();
      try {
        const location = redirect.headers().location;
        const f = location ? await external.get(location, { timeout: 30000 }) : redirect;
        const body = await f.body();
        if (f.status() !== 200) {
          const code = body.toString().match(/<Code>([^<]+)<\/Code>/)?.[1];
          fs.writeFileSync(path.join(dir, 'download-error.json'), JSON.stringify({ file: o.name, status: f.status(), code: code || 'non-S3 error' }, null, 2));
        }
        expect(f.status(), `download ${o.name}`).toBe(200);
        expect(body.length, `nonempty ${o.name}`).toBeGreaterThan(0);
        fs.writeFileSync(path.join(dir, path.basename(o.name)), body);
      } finally { await external.dispose(); }
    }
    return { count: outputs.length };
  });
  await check('reproducibility record identifies outputs', async () => {
    const r = await page.request.get(`${BASE_URL}/api/runs/${run}/reproducibility-record`, { timeout: 45000 });
    expect(r.status()).toBe(200);
    const j = await r.json();
    const safe = JSON.parse(JSON.stringify(j, (k, v) => /url|uri|token|secret|password/i.test(k) ? '[redacted]' : v));
    fs.writeFileSync(path.join(dir, 'reproducibility-record.json'), JSON.stringify(safe, null, 2));
    expect(j.outputs?.length).toBeGreaterThan(0);
    return { outputs: j.outputs.length, fields: Object.keys(j) };
  });
  await check('real chat opens a completed workflow without debug route', async () => {
    await page.goto(`${BASE_URL}/?session=chat-1790955154245-s17yy1qla`, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await expect(page.getByTestId('chat-input')).toBeVisible({ timeout: 30000 });
    await page.waitForTimeout(5000);
    await page.screenshot({ path: path.join(dir, 'live-session.png') });
    fs.writeFileSync(path.join(dir, 'live-session.txt'), await page.locator('body').innerText());
    await expect(page.getByText(/Predict ADMET Properties/i).first()).toBeVisible();
    expect(page.url()).not.toContain('/debug/');
    return { url: page.url() };
  });
  for (const [id, label] of [['after-tab-outputs', 'outputs'], ['after-tab-record', 'record'], ['after-tab-summary', 'summary']]) {
    await check(`real ${label} tab`, async () => {
      await page.getByTestId(id).click({ timeout: 12000 });
      await page.waitForTimeout(2000);
      // Dismiss the real optional feedback prompt through its normal UI.
      // Never submit fabricated ratings or hide it by editing the DOM.
      const notNow = page.getByRole('button', { name: 'Not now', exact: true });
      if (await notNow.isVisible()) {
        await notNow.click();
        await expect(notNow).not.toBeVisible();
      }
      await page.screenshot({ path: path.join(dir, `live-${label}.png`) });
      await page.screenshot({ path: path.join(dir, `panel-${label}.png`), clip: { x: 1080, y: 84, width: 840, height: 974 } });
      fs.writeFileSync(path.join(dir, `live-${label}.txt`), await page.locator('body').innerText());
      return { captured: true };
    });
  }
  evidence.technicalChecksPassed = failures.length === 0;
  evidence.releaseStatus = 'HOLD: scientific, editorial, localization and audiovisual review required';
  fs.writeFileSync(path.join(dir, 'live-audit.json'), JSON.stringify(evidence, null, 2));
  expect(failures, 'Every failed or unavailable release check is blocking').toEqual([]);
});
