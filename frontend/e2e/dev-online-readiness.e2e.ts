/** Live dev requests and direct scientific tools. No Nextflow dispatch or safety override. */
import { test, expect } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { loginAsFixture, BASE_URL } from './_fixture-login';
import { readConnectorSession } from '../server/connector-session';

test('online readiness: drug-development requests and isolation', async ({ page, playwright }) => {
  test.setTimeout(12 * 60_000);
  expect(new URL(BASE_URL).hostname, 'must target dev, never production').toBe('dev-public.biomate.ai');
  const output = path.resolve(process.env.DEV_READINESS_OUTPUT || `../docs/qa/20261107-dev-online-readiness/run-${Date.now()}`);
  mkdirSync(output, { recursive: true });
  const checks: Array<{ name: string; passed: boolean; detail: unknown }> = [];
  const record = (name: string, passed: boolean, detail: unknown) => {
    checks.push({ name, passed, detail });
    console.log(`${passed ? 'PASS' : 'FAIL'} ${name}: ${JSON.stringify(detail)}`);
  };
  let projectId: string | undefined;
  const sessions: string[] = [];
  try {
    await loginAsFixture(page);
    const health = await page.request.get(`${BASE_URL}/api/health`);
    const healthBody = await health.json();
    record('service health', health.ok() && healthBody.status === 'ok' && healthBody.services?.galaxy?.connected === true, healthBody);
    const version = await page.request.get(`${BASE_URL}/api/galaxy/version`);
    const versionBody = await version.json();
    record('Galaxy API available', version.ok() && typeof versionBody.version_major === 'string' && !!versionBody.version_major && !versionBody.error,
      { status: version.status(), version: versionBody.version_major });

    // An independent request context has no cached fixture cookie or Bearer token.
    const anonymous = await playwright.request.newContext();
    try {
      const denied = await anonymous.get(`${BASE_URL}/api/projects`);
      record('anonymous project access denied', denied.status() === 401, { status: denied.status() });
    } finally { await anonymous.dispose(); }
    const absent = await page.request.get(`${BASE_URL}/api/projects/00000000-0000-0000-0000-000000000000`);
    record('nonexistent project concealed', absent.status() === 404, { status: absent.status() });

    const create = await page.request.post(`${BASE_URL}/api/projects`, { data: { name: `Dev scientific acceptance ${Date.now()}`, primaryDomain: 'drug_discovery' } });
    const created = await create.json();
    projectId = created.project?.id;
    expect(create.ok() && typeof projectId === 'string', 'create one isolated acceptance project').toBe(true);
    await page.goto(BASE_URL, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await expect(page.getByTestId('chat-input')).toBeVisible({ timeout: 45_000 });
    await page.screenshot({ path: path.join(output, 'authenticated-workbench.png') });
    record('authenticated workbench visible', true, { screenshot: 'authenticated-workbench.png' });

    const cases = [
      { name: 'small-molecule ADMET', expected: /admet|absorption|toxicity|developability/i,
        prompt: 'Screen caffeine CN1C=NC2=C1C(=O)N(C(=O)N2C)C and aspirin CC(=O)OC1=CC=CC=C1C(=O)O for ADMET liabilities and rank by developability.' },
      { name: 'peptide properties', expected: /peptide|protein.*propert|physicochemical/i,
        prompt: 'Calculate the physicochemical properties, molecular weight and isoelectric point of peptide sequence ACDEFGHIKLMNPQRSTVWY.' },
      { name: 'oncology target evidence', expected: /target|opentarget|drug.*discover|evidence/i,
        prompt: 'Use Open Targets to retrieve evidence linking EGFR to non-small-cell lung carcinoma and prioritize its drug discovery relevance.' },
    ];
    const selected = process.env.DEV_READINESS_CASES?.split(',').map(value => value.trim());
    if (selected) expect(selected.every(name => cases.some(item => item.name === name)), 'unknown readiness case').toBe(true);
    for (const item of cases.filter(item => !selected || selected.includes(item.name))) {
      const sessionId = `dev-acceptance-${crypto.randomUUID()}`;
      sessions.push(sessionId);
      try {
        const response = await page.request.post(`${BASE_URL}/api/chat/stream`, {
          data: { message: item.prompt, stream: true, context: { sessionId, projectId, previousMessages: [] } }, timeout: 180_000,
        });
        // Reuse the connector's strict SSE contract: HTTP success, final response,
        // done.ok=true, and no error event. Merely mentioning a workflow cannot pass.
        const responseBody = await response.body();
        const parsed = await readConnectorSession(new Response(responseBody, {
          status: response.status(), headers: { 'content-type': response.headers()['content-type'] || '' },
        }));
        const workflow = parsed.workflow_suggested;
        const route = workflow ? {
          name: workflow.workflow_name || workflow.workflow_ga?.name || workflow.chain_display_name,
          type: workflow.workflow_type || workflow.execution_engine,
          nextflowPath: workflow.nextflow_path,
          chain: workflow.chain_name,
          steps: workflow.chain_steps || workflow.pipeline_steps,
        } : null;
        const matched = item.expected.test(JSON.stringify(route));
        // Target identification may legitimately execute as a direct chat tool,
        // not a draft workflow. Require its structured result and requested OT
        // evidence, never a keyword match in the answer or an invented card.
        let targetEvidence: any = null;
        let targetRequest: any = null;
        let peptideEvidence: any = null;
        if (item.name === 'oncology target evidence' || item.name === 'peptide properties') {
          for (const frame of responseBody.toString('utf8').split(/\r?\n\r?\n/)) {
            if (!/^event: tool_event\r?$/m.test(frame)) continue;
            const lines = frame.split(/\r?\n/).filter(line => line.startsWith('data:'));
            const event = JSON.parse(lines.map(line => line.slice(5).replace(/^ /, '')).join('\n'));
            if (event.type === 'tool_result' && event.name === 'run_code' && !event.error) {
              const value = typeof event.output === 'string' ? JSON.parse(event.output) : event.output;
              if (value?.exit_code === 0 && typeof value.stdout === 'string') {
                try { peptideEvidence = { exitCode: value.exit_code, ...JSON.parse(value.stdout.trim()) }; } catch { /* non-JSON is not the declared scientific output contract */ }
              }
            }
            if (event.name === 'identify_targets' && event.input) targetRequest = event.input;
            if (event.type !== 'tool_result' || event.name !== 'identify_targets' || event.error) continue;
            const value = typeof event.output === 'string' ? JSON.parse(event.output) : event.output;
            targetEvidence = {
              status: value?.status, targets: value?.targets,
              channels: value?.channels_run, failedChannels: Object.keys(value?.channel_errors || {}),
              // These two public channels do not use access keys. Preserve their
              // complete error message for diagnosis, removing any URL queries.
              sourceErrors: Object.fromEntries(Object.entries(value?.channel_errors || {})
                .filter(([name]) => ['genetics_ot', 'ppi_string'].includes(name))
                .map(([name, error]) => [name, String(error).replace(/(https?:\/\/[^\s?]+)\?\S+/g, '$1?[redacted]')])),
              failureKinds: Object.fromEntries(Object.entries(value?.channel_errors || {}).map(([name, error]) => [name,
                /no disease_id/i.test(String(error)) ? 'missing disease identifier'
                  : /HTTP Error \d+/.exec(String(error))?.[0]
                    || (/timeout|timed out/i.test(String(error)) ? 'timeout'
                      : /no partners/i.test(String(error)) ? 'no network partners' : 'source error'),
              ])),
              ranking: value?.ranking,
            };
          }
        }
        const positiveResult = item.name === 'oncology target evidence'
          ? targetEvidence?.status === 'ok' && targetEvidence.targets?.some((target: any) => target.target === 'EGFR')
            && targetEvidence.channels?.includes('genetics_ot') && !targetEvidence.failedChannels.includes('genetics_ot')
          : item.name === 'peptide properties'
            ? peptideEvidence?.exitCode === 0 && peptideEvidence.sequence === 'ACDEFGHIKLMNPQRSTVWY'
              && Math.abs(Number(peptideEvidence.molecular_weight) - 2395.7134) < 0.02
              && Math.abs(Number(peptideEvidence.isoelectric_point) - 6.78455) < 0.01
              && !route
            : parsed.state === 'workflow_ready' && !!route && matched;
        record(item.name, !!positiveResult && !parsed.run_id, {
          state: parsed.state, route, autoDispatched: !!parsed.run_id,
          ...(targetEvidence ? { targetEvidence } : {}),
          ...(targetRequest ? { targetRequest } : {}),
          ...(peptideEvidence ? { peptideEvidence } : {}),
          responseExcerpt: parsed.response.slice(0, 700),
          clarification: parsed.clarification,
        });
      } catch (error) {
        record(item.name, false, { error: error instanceof Error ? error.message : String(error) });
      }
    }
    const runs = await page.request.get(`${BASE_URL}/api/workflows/runs?projectId=${encodeURIComponent(projectId!)}`);
    const runBody = await runs.json();
    record('requests launch no Nextflow runs', runs.ok() && Array.isArray(runBody) && runBody.length === 0, {
      status: runs.status(), runCount: Array.isArray(runBody) ? runBody.length : null,
    });
  } catch (error) {
    record('preflight execution', false, { error: error instanceof Error ? error.message : String(error) });
    throw error;
  } finally {
    for (const sessionId of sessions) {
      try {
        const deleted = await page.request.delete(`${BASE_URL}/api/sessions/${encodeURIComponent(sessionId)}`);
        record(`cleanup session ${sessionId}`, deleted.ok() || deleted.status() === 404, { status: deleted.status() });
      } catch (error) { record(`cleanup session ${sessionId}`, false, { error: String(error) }); }
    }
    if (projectId) {
      try {
        const deleted = await page.request.delete(`${BASE_URL}/api/projects/${projectId}`);
        record('cleanup acceptance project', deleted.ok(), { status: deleted.status() });
      } catch (error) { record('cleanup acceptance project', false, { error: String(error) }); }
    }
    writeFileSync(path.join(output, 'preflight-results.json'), JSON.stringify({
      testedAt: new Date().toISOString(), target: BASE_URL, scope: 'HTTP drafts, direct target evidence and authenticated workbench; not Nextflow execution or scientific accuracy', checks,
    }, null, 2) + '\n');
  }
  expect(checks.filter(check => !check.passed), 'every failed preflight must fail the test').toEqual([]);
});
