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
  const response = await fetch(base + '/api/chat/stream', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ message: 'Explain briefly how I can review a workflow plan before executing it in BioMate. Do not generate or execute a workflow.', context: {} }),
    signal: AbortSignal.timeout(180000),
  });
  const result = await readConnectorSession(response);
  const proof = {
    date: new Date().toISOString(), scope: 'Local repaired parser consuming a real deployed chat SSE response; not a deployed connector-route test',
    passed: Boolean(result.response.trim()), responseCharacters: result.response.length,
    state: result.state, isMultiIntent: result.isMultiIntent, hasWorkflow: Boolean(result.workflow_suggested),
    fields: Object.keys(result),
  };
  fs.writeFileSync('docs/qa/20261009-connector-workflows/compatibility/session-proof.json', JSON.stringify(proof, null, 2) + '\n');
  console.log(JSON.stringify(proof));
  if (!proof.passed) process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
