/** Real dev chat response through the repaired parser; does not launch a workflow. */
import fs from 'node:fs';
import { FIXTURE_EMAIL, FIXTURE_PASSWORD, E2E_TOKEN } from '../frontend/e2e/_fixture-login';
import { readConnectorSession } from '../frontend/server/connector-session';

async function main() {
  const base = 'https://dev-public.biomate.ai';
  const auth = await fetch(base + '/api/auth/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-E2E-Test-Token': E2E_TOKEN },
    body: JSON.stringify({ email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD }),
  });
  if (!auth.ok) throw new Error(`Login HTTP ${auth.status}`);
  const { token } = await auth.json() as { token: string };
  const deployedRoute = process.env.CONNECTOR_SESSION_ROUTE_PROOF === '1';
  const message = 'Explain briefly how I can review a workflow plan before executing it in BioMate. Do not generate or execute a workflow.';
  const response = await fetch(base + (deployedRoute ? '/tools/biomate_session' : '/api/chat/stream'), {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(deployedRoute ? { goal: message } : { message, context: {} }),
    signal: AbortSignal.timeout(180000),
  });
  if (!response.ok) throw new Error(`Connector session HTTP ${response.status}`);
  const result = deployedRoute ? await response.json() as any : await readConnectorSession(response);
  const proof = {
    date: new Date().toISOString(), scope: deployedRoute ? 'Deployed connector session route; no workflow execution' : 'Local repaired parser consuming a real deployed chat SSE response; not a deployed connector-route test',
    passed: Boolean(result.response.trim()), responseCharacters: result.response.length,
    state: result.state, isMultiIntent: result.isMultiIntent, hasWorkflow: Boolean(result.workflow_suggested),
    fields: Object.keys(result),
  };
  fs.writeFileSync('docs/qa/20261009-connector-workflows/compatibility/' + (deployedRoute ? 'session-deployed-proof.json' : 'session-proof.json'), JSON.stringify(proof, null, 2) + '\n');
  console.log(JSON.stringify(proof));
  if (!proof.passed) process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
