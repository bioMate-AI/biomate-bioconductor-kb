/** Real bounded CPU execution through the authenticated online platform. No mocks. */
import { test, expect, type APIRequestContext } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { BASE_URL, loginAsFixture } from './_fixture-login';

const WORKFLOW = 'nextflow_nfcore/subworkflows/pharmacology/calculate_physicochemical_properties/main.nf';

test('scientific properties: real ethanol artifacts and invalid-input rejection', async ({ page, playwright }) => {
  test.setTimeout(20 * 60_000);
  expect(new URL(BASE_URL).hostname).toBe('dev-public.biomate.ai');
  const output = path.resolve(`../docs/qa/20261107-dev-online-readiness/scientific-${Date.now()}`);
  mkdirSync(output, { recursive: true });
  const evidence: any = { target: BASE_URL, workflow: WORKFLOW, runs: [] };
  let projectId: string | undefined;
  let activeRun: string | undefined;
  const anonymous = await playwright.request.newContext();
  const request = page.request;
  const get = async (url: string) => {
    const result = await request.get(BASE_URL + url, { timeout: 45_000 });
    expect(result.ok(), `GET ${url}: HTTP ${result.status()}`).toBe(true);
    return result.json();
  };
  async function launch(smiles: string) {
    const response = await request.post(BASE_URL + '/api/workflows/execute', {
      timeout: 120_000,
      data: {
        projectId,
        workflowDefinition: {
          id: 10770, name: 'Calculate Physicochemical Properties', workflow_type: 'nextflow',
          nextflow_path: WORKFLOW, parameters: { smiles_string: smiles },
        },
        executionConfig: { computeConfig: { executor: 'awsbatch', cpus: 1, memory_gb: 2 } },
      },
    });
    const body = await response.json();
    expect(response.ok(), `Scientific execution rejected: ${JSON.stringify(body)}`).toBe(true);
    expect(typeof body.runId).toBe('string');
    activeRun = body.runId;
    evidence.runs.push({ runId: body.runId, smiles, launchStatus: body.status });
    return body.runId as string;
  }
  async function wait(runId: string) {
    const deadline = Date.now() + 8 * 60_000;
    let previous = '';
    while (Date.now() < deadline) {
      const run = await get('/api/workflows/runs/' + runId);
      const status = run.execution?.status;
      expect(typeof status, 'run record has an explicit status').toBe('string');
      if (status !== previous) {
        console.log(`Scientific run ${runId}: ${status}`);
        previous = status;
      }
      if (['completed', 'failed', 'cancelled', 'paused'].includes(status)) {
        activeRun = undefined;
        Object.assign(evidence.runs.find((value: any) => value.runId === runId), {
          finalStatus: status, nextflowRunId: run.execution?.nextflowRunId,
          error: run.execution?.errorMessage || run.execution?.error,
        });
        return run;
      }
      await new Promise(resolve => setTimeout(resolve, 4000));
    }
    throw new Error('Scientific execution exceeded the bounded eight-minute polling window');
  }
  async function download(item: any, filename: string) {
    expect(typeof item.downloadUrl).toBe('string');
    const url = new URL(item.downloadUrl, BASE_URL);
    // Never send the fixture's Authorization header to an external presigned S3 URL.
    const client: APIRequestContext = url.origin === new URL(BASE_URL).origin ? request : anonymous;
    expect(url.protocol).toBe('https:');
    const response = await client.get(url.href, { timeout: 45_000 });
    expect(response.ok(), `download ${filename}: HTTP ${response.status()}`).toBe(true);
    const content = await response.text();
    expect(content.length).toBeGreaterThan(0);
    writeFileSync(path.join(output, filename), content);
    return content;
  }
  try {
    await loginAsFixture(page);
    evidence.build = await get('/build-info.json');
    const response = await request.post(BASE_URL + '/api/projects', { data: {
      name: `Scientific artifact acceptance ${Date.now()}`, primaryDomain: 'drug_discovery',
    } });
    const created = await response.json();
    projectId = created.project?.id;
    expect(response.ok() && typeof projectId === 'string').toBe(true);
    const positiveId = await launch('CCO');
    const positive = await wait(positiveId);
    expect(positive.execution.status, JSON.stringify(positive.execution)).toBe('completed');
    const listed = await get('/api/runs/' + positiveId + '/outputs');
    expect(Array.isArray(listed.outputs)).toBe(true);
    const csv = listed.outputs.find((item: any) => item.name === 'physicochemical_properties.csv');
    const json = listed.outputs.find((item: any) => item.name === 'calculate_physicochemical_properties_results.json');
    expect(csv, 'scientific CSV is published and downloadable').toBeTruthy();
    expect(json, 'machine-readable result is published').toBeTruthy();
    const text = await download(csv, 'ethanol-properties.csv');
    const rows = text.replace(/\r/g, '').trim().split('\n').map(line => line.split(','));
    expect(rows[0]).toEqual(['Property', 'Value']);
    expect(rows.every(row => row.length === 2)).toBe(true);
    expect(new Set(rows.slice(1).map(row => row[0])).size).toBe(rows.length - 1);
    const values = Object.fromEntries(rows.slice(1));
    expect(values.SMILES).toBe('CCO');
    expect(Number(values['Molecular Weight'])).toBeCloseTo(46.07, 2);
    expect(Number(values['Heavy Atoms'])).toBe(3);
    expect(Number(values['H-Bond Donors'])).toBe(1);
    expect(Number(values['Molar Refractivity'])).toBeCloseTo(12.76, 2);
    expect(Number(values.QED)).toBeGreaterThan(0);
    expect(Number(values.QED)).toBeLessThan(1);
    expect(values).not.toHaveProperty('Estimated logD7.4');
    expect(values).not.toHaveProperty('Drug-likeness Score');
    const result = JSON.parse(await download(json, 'ethanol-result.json'));
    expect(result.success).toBe(true);
    evidence.ethanol = { passed: true, descriptors: values };

    const negativeId = await launch('not-a-molecule');
    expect(negativeId).not.toBe(positiveId);
    const negative = await wait(negativeId);
    expect(negative.execution.status).toBe('failed');
    const logs = await get('/api/workflows/runs/' + negativeId + '/logs');
    const reason = JSON.stringify(logs);
    expect(reason, 'failure must be invalid SMILES, not infrastructure or compilation').toMatch(/ValueError: ERROR: Invalid SMILES string provided/);
    evidence.invalidInput = { passed: true, reason: 'Actual workflow rejected invalid SMILES' };
  } catch (error) {
    evidence.failure = error instanceof Error ? error.message : String(error);
    throw error;
  } finally {
    if (activeRun) {
      try {
        const cancelled = await request.post(BASE_URL + '/api/workflows/runs/' + activeRun + '/cancel', {
          data: { reason: 'Bounded scientific acceptance test cleanup' }, timeout: 30_000,
        });
        evidence.cancelRequested = { runId: activeRun, accepted: cancelled.ok() };
      } catch (error) { evidence.cancelRequested = { runId: activeRun, accepted: false, error: String(error) }; }
    }
    evidence.projectId = projectId;
    if (projectId && !activeRun) {
      try {
        const deleted = await request.delete(BASE_URL + '/api/projects/' + projectId);
        evidence.projectCleanup = { status: deleted.status(), passed: deleted.ok() };
        expect(deleted.ok(), 'clean up the isolated terminal test project').toBe(true);
      } catch (error) { evidence.projectCleanup = { passed: false, error: String(error) }; evidence.failure ||= 'Project cleanup failed'; }
    }
    evidence.finishedAt = new Date().toISOString();
    writeFileSync(path.join(output, 'scientific-results.json'), JSON.stringify(evidence, null, 2) + '\n');
    await anonymous.dispose();
  }
  expect(evidence.failure).toBeUndefined();
});
