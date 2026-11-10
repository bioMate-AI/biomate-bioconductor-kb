/** Real project-file selection and numeric comparison on dev; no API mocks. */
import { test, expect } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { loginAsFixture, BASE_URL } from './_fixture-login';
import { readConnectorSession } from '../server/connector-session';

test('two explicit project files stay bound through a real comparison', async ({ page }) => {
  test.setTimeout(8 * 60_000);
  expect(new URL(BASE_URL).hostname).toBe('dev-public.biomate.ai');
  const output = path.resolve(`../docs/qa/20261108-dev-coherence/run-${Date.now()}`);
  mkdirSync(output, { recursive: true });
  const evidence: any = { target: BASE_URL, files: [], tools: [], cleanup: [] };
  let projectId: string | undefined;
  let sessionId: string | undefined;
  const fixtures = [
    { name: 'assay-A.csv', text: 'compound_id,ic50_uM\nCMP_A,12\nCMP_B,3\nCMP_C,7\n' },
    // Different row order and partial overlap require an identity join, not zip.
    { name: 'assay-B.csv', text: 'compound_id,ic50_uM\nCMP_C,6\nCMP_A,4\nCMP_D,8\n' },
    { name: 'do-not-select.csv', text: 'compound_id,ic50_uM\nCMP_A,9999\nCMP_C,9998\n' },
  ];
  try {
    await loginAsFixture(page);
    const build = await page.request.get(BASE_URL + '/build-info.json');
    expect(build.ok()).toBe(true);
    evidence.buildBefore = await build.json();
    const created = await page.request.post(BASE_URL + '/api/projects', {
      data: { name: `Dev file comparison ${Date.now()}`, primaryDomain: 'drug_discovery' },
    });
    expect(created.ok()).toBe(true);
    projectId = (await created.json()).project?.id;
    expect(typeof projectId).toBe('string');
    evidence.projectId = projectId;
    for (const fixture of fixtures) {
      const response = await page.request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
        multipart: { file: { name: fixture.name, mimeType: 'text/csv', buffer: Buffer.from(fixture.text) } },
      });
      expect(response.ok(), `upload ${fixture.name}: HTTP ${response.status()}`).toBe(true);
      const file = (await response.json()).file;
      expect(typeof file?.id).toBe('string');
      evidence.files.push({ id: file.id, name: file.name, sha256: createHash('sha256').update(fixture.text).digest('hex') });
    }
    const [a, b, distractor] = evidence.files;
    expect(new Set(evidence.files.map((file: any) => file.id)).size).toBe(3);
    // Exercise the user's Data Hub flow, including explicit project activation.
    // Fresh-session chat deep links are a separate regression: the current root
    // route does not activate their project query (retain the failed first run).
    await page.goto(`${BASE_URL}/projects?project=${projectId}`, { waitUntil: 'domcontentloaded' });
    await expect.poll(() => page.evaluate(() => localStorage.getItem('biomate-active-project-id'))).toBe(projectId);
    await page.goto(`${BASE_URL}/files?file=${a.id}`, { waitUntil: 'domcontentloaded' });
    await expect(page.getByTestId('dataset-object-name')).toHaveText(a.name, { timeout: 30_000 });
    await page.getByTestId('dataset-object-analyze').click();
    const references = page.getByTestId('composer-dataset-ref');
    await expect(references).toHaveCount(1, { timeout: 30_000 });
    await expect(references.first()).toHaveText(a.name);
    await expect(page.getByTestId('chat-input')).toHaveValue('');
    await page.getByTestId('chat-attach-data-button').click();
    const picker = page.getByRole('dialog');
    await picker.getByRole('button', { name: /Project files|项目文件/ }).click();
    const fileName = picker.getByText(b.name, { exact: true });
    await expect(fileName).toBeVisible();
    await fileName.locator('..').locator('..').getByRole('button', { name: /^Use$|^使用$/ }).click();
    await expect(references).toHaveCount(2);
    expect(await references.allTextContents()).toEqual([a.name, b.name]);
    await page.screenshot({ path: path.join(output, 'two-selected-files.png') });

    const prompt = 'Compare the two selected assay CSV result files by compound_id, not row order. '
      + 'Use assay-A.csv as A and assay-B.csv as B. Calculate the difference B minus A in micromolar units. '
      + 'Use actual file contents, not example data. Pass both selected file IDs as input_datasets to run_code '
      + 'and read their staged CSV paths for the calculation; do not copy preview values into code literals. '
      + 'Execute the calculation and print one JSON object with '
      + 'common:[{compound_id,file_a_uM,file_b_uM,delta_B_minus_A_uM}], only_in_a:[compound IDs], only_in_b:[compound IDs]. '
      + 'Then summarize the actual results in the answer. Do not infer statistical significance or clinical efficacy.';
    await page.getByTestId('chat-input').fill(prompt);
    const pending = page.waitForResponse(response => response.url().endsWith('/api/chat/stream')
      && response.request().method() === 'POST', { timeout: 180_000 });
    await page.getByTestId('chat-send-button').click();
    const response = await pending;
    evidence.contentType = response.headers()['content-type'];
    expect(evidence.contentType).toMatch(/text\/event-stream;\s*charset=utf-8/i);
    const request = response.request().postDataJSON();
    sessionId = request.context?.sessionId;
    evidence.selectedReferences = request.context?.datasetReferences;
    expect(evidence.selectedReferences).toEqual([{ id: a.id, name: a.name }, { id: b.id, name: b.name }]);
    expect(request.context?.projectId).toBe(projectId);
    expect(JSON.stringify(evidence.selectedReferences)).not.toContain(distractor.id);
    const bytes = await response.body();
    const parsed = await readConnectorSession(new Response(bytes, {
      status: response.status(), headers: { 'content-type': response.headers()['content-type'] || '' },
    }));
    evidence.response = parsed.response;
    expect(parsed.run_id).toBeUndefined();
    expect(parsed.workflow_suggested).toBeNull();
    const calls = new Map<string, any>();
    const results: any[] = [];
    for (const frame of bytes.toString('utf8').split(/\r?\n\r?\n/)) {
      if (!/^event: tool_event\r?$/m.test(frame)) continue;
      const event = JSON.parse(frame.split(/\r?\n/).filter(line => line.startsWith('data:'))
        .map(line => line.slice(5).replace(/^ /, '')).join('\n'));
      evidence.tools.push(event);
      if (event.type === 'tool_call' && event.name === 'run_code') calls.set(event.tool_use_id, event.input);
      if (event.type !== 'tool_result' || event.name !== 'run_code' || event.error) continue;
      const value = typeof event.output === 'string' ? JSON.parse(event.output) : event.output;
      if (value?.exit_code !== 0 || typeof value.stdout !== 'string' || !calls.has(event.tool_use_id)) continue;
      try {
        const actual = JSON.parse(value.stdout.trim());
        if (Array.isArray(actual.common)) results.push({ actual, stagedNames: Object.keys(value.staged_inputs || {}) });
      } catch { /* Only the declared structured scientific result can pass. */ }
    }
    expect(results.length, 'a real successful tool must produce the comparison').toBeGreaterThan(0);
    const result = results[results.length - 1];
    evidence.comparison = result;
    expect(result.stagedNames.sort()).toEqual([a.name, b.name].sort());
    expect([...result.actual.common].sort((x, y) => x.compound_id.localeCompare(y.compound_id))).toEqual([
      { compound_id: 'CMP_A', file_a_uM: 12, file_b_uM: 4, delta_B_minus_A_uM: -8 },
      { compound_id: 'CMP_C', file_a_uM: 7, file_b_uM: 6, delta_B_minus_A_uM: -1 },
    ]);
    expect(result.actual.only_in_a).toEqual(['CMP_B']);
    expect(result.actual.only_in_b).toEqual(['CMP_D']);
    expect(parsed.response).toContain('CMP_A');
    expect(parsed.response).toContain('CMP_C');
    // A mathematical Unicode minus is equivalent to an ASCII hyphen, not an error.
    expect(parsed.response).toMatch(/[-−]8(?:\.0+)?\b/);
    expect(parsed.response).toMatch(/[-−]1(?:\.0+)?\b/);
    expect(parsed.response).not.toMatch(/Âµ|âˆ|â†|\uFFFD/);
    expect(parsed.response).not.toMatch(/9999|9998/);
    const runs = await page.request.get(`${BASE_URL}/api/workflows/runs?projectId=${projectId}`);
    expect(runs.ok()).toBe(true);
    expect(await runs.json()).toEqual([]);
    await expect(page.getByTestId('chat-input')).toBeEnabled({ timeout: 30_000 });
    await page.screenshot({ path: path.join(output, 'comparison-result.png'), fullPage: true });
    // A copied link must work without a project remembered in this browser.
    // Clear only this test browser's selection, never application/server data.
    await page.evaluate(() => localStorage.removeItem('biomate-active-project-id'));
    let unsolicitedChats = 0;
    page.on('request', request => {
      if (request.method() === 'POST' && request.url().endsWith('/api/chat/stream')) unsolicitedChats++;
    });
    await page.goto(`${BASE_URL}/?project=${projectId}&attachFile=${a.id}&attachFile=${b.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect.poll(() => page.evaluate(() => localStorage.getItem('biomate-active-project-id'))).toBe(projectId);
    await expect(references).toHaveCount(2, { timeout: 30_000 });
    expect(await references.allTextContents()).toEqual([a.name, b.name]);
    await expect(page.getByTestId('chat-input')).toHaveValue('');
    expect(unsolicitedChats, 'opening file links must never submit analysis').toBe(0);
    evidence.freshLink = { selectedNames: await references.allTextContents(), unsolicitedChats };
    await page.screenshot({ path: path.join(output, 'fresh-link-two-files.png') });
    const after = await page.request.get(BASE_URL + '/build-info.json');
    expect(after.ok()).toBe(true);
    evidence.buildAfter = await after.json();
    expect(evidence.buildAfter).toEqual(evidence.buildBefore);
    evidence.passed = true;
  } catch (error) {
    evidence.passed = false;
    evidence.failure = error instanceof Error ? error.message : String(error);
    await page.screenshot({ path: path.join(output, 'failure.png'), fullPage: true }).catch(() => {});
    throw error;
  } finally {
    if (sessionId) {
      try {
        const result = await page.request.delete(`${BASE_URL}/api/sessions/${encodeURIComponent(sessionId)}`);
        evidence.cleanup.push({ resource: 'session', status: result.status(), passed: result.ok() || result.status() === 404 });
      } catch { evidence.cleanup.push({ resource: 'session', passed: false }); }
    }
    if (projectId) {
      for (const file of evidence.files) {
        try {
          const result = await page.request.delete(`${BASE_URL}/api/projects/${projectId}/files/${file.id}`);
          evidence.cleanup.push({ resource: file.name, status: result.status(), passed: result.ok() });
        } catch { evidence.cleanup.push({ resource: file.name, passed: false }); }
      }
      try {
        const result = await page.request.delete(`${BASE_URL}/api/projects/${projectId}`);
        evidence.cleanup.push({ resource: 'project', status: result.status(), passed: result.ok() });
      } catch { evidence.cleanup.push({ resource: 'project', passed: false }); }
    }
    if (evidence.cleanup.some((item: any) => !item.passed)) evidence.passed = false;
    evidence.finishedAt = new Date().toISOString();
    writeFileSync(path.join(output, 'comparison-results.json'), JSON.stringify(evidence, null, 2) + '\n');
  }
  expect(evidence.passed, 'scientific and cleanup assertions must all pass').toBe(true);
});
