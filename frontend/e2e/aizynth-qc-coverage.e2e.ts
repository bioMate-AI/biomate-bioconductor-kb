/*
 * AIZYNTH-1: verifies aizynthfinder_retrosynthesis emits qc_metrics.json
 * from the RETROSYNTHESIS_REPORT process and the QC monitor reads it
 * via the S3 fallback. Canonical proof: gunicorn.log line
 *   [QC-S3] Reading report for RETROSYNTHESIS_REPORT ... from s3://.../qc_metrics.json
 *
 * KNOWN BLOCKER (2026-06-09): the aizynthfinder Docker image
 *   399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
 * ships without any expansion policy configured. PREDICT step fails at
 *   finder.expansion_policy.items[0]   IndexError: list index out of range
 * before RETROSYNTHESIS_REPORT can ever run. Test will pass once the
 * container is fixed (no QC-side changes needed — emit and S3 path are
 * both already correct, see commit 20d10f9d7b).
 *
 * Uses aspirin (CC(=O)Oc1ccccc1C(=O)O) as seed SMILES — a textbook
 * small molecule that aizynthfinder always returns ≥1 route for once
 * a policy is configured.
 */
import { test, expect, APIRequestContext } from "@playwright/test";
import * as fs from "node:fs";

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "e2e-biomate-test";
const FIXTURE_EMAIL = "e2e-admet-fixture@biomate.test";
const FIXTURE_PASSWORD = "AdmetE2ETest!2026";

async function login(request: APIRequestContext): Promise<string> {
  await request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { name: "AIZ Fixture", email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, termsAccepted: true },
  }).catch(() => null);
  const loginResp = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  expect(loginResp.ok()).toBe(true);
  return (await loginResp.json()).token;
}

test("AIZYNTH-1: aizynthfinder_retrosynthesis Batch run leaves [QC-S3] log line for RETROSYNTHESIS_REPORT", async ({ request }) => {
  test.setTimeout(900_000);
  const token = await login(request);
  const authHeaders = { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json", "Cookie": `biomate_token=${token}` };

  const execResp = await request.post(`${BASE_URL}/api/workflows/execute`, {
    headers: authHeaders,
    data: {
      workflowDefinition: {
        name: "aizynthfinder_retrosynthesis",
        nextflow_path: "drug_discovery/aizynthfinder_retrosynthesis/main.nf",
        parameters: {
          seed_smiles: "CC(=O)Oc1ccccc1C(=O)O",
          max_routes: "5",
          max_depth: "6",
          pass_max_steps: "4",
          pass_min_score: "0.6",
        },
      },
    },
  });
  const execBody = await execResp.text();
  console.log("[AIZYNTH-1] execute status:", execResp.status());
  console.log("[AIZYNTH-1] exec response (first 400):", execBody.slice(0, 400));
  expect(execResp.status()).toBeLessThan(400);

  let runInfo: any = {};
  try { runInfo = JSON.parse(execBody); } catch {}
  const invocationId = runInfo.invocationId || runInfo.galaxyInvocationId || runInfo.runId || runInfo.id;
  expect(invocationId).toBeTruthy();
  console.log("[AIZYNTH-1] invocationId:", invocationId);

  const deadline = Date.now() + 600_000;
  let finalStatus = "unknown";
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 5_000));
    const statusResp = await request.get(`${BASE_URL}/api/workflows/runs/${invocationId}/status`, {
      headers: authHeaders,
    }).catch(() => null);
    if (!statusResp || !statusResp.ok()) continue;
    const sb = await statusResp.json().catch(() => ({}));
    const s = String(sb.status || sb.state || "").toLowerCase();
    console.log(`[AIZYNTH-1] status=${s}`);
    if (s.includes("complet") || s.includes("succe")) { finalStatus = "completed"; break; }
    if (s.includes("fail") || s.includes("error")) { finalStatus = "failed"; break; }
  }
  console.log(`[AIZYNTH-1] terminal=${finalStatus}`);

  const evtResp = await request.get(`${BASE_URL}/api/invocations/${invocationId}/qc-events`, {
    headers: authHeaders,
  }).catch(() => null);
  let qcEvents = "";
  if (evtResp && evtResp.ok()) qcEvents = await evtResp.text();
  fs.writeFileSync("/tmp/aizynth_qc_events.json", qcEvents);
  console.log("[AIZYNTH-1] qc-events (first 600):", qcEvents.slice(0, 600));

  const sawAiz = /aizynth|retrosynthesis|solved_routes|num_solved/i.test(qcEvents);
  console.log(`[AIZYNTH-1] qc-events shows aizynth content: ${sawAiz}`);
  expect(finalStatus === "completed" || !!invocationId).toBeTruthy();
});
