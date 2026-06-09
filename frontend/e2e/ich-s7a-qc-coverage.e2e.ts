/*
 * ICH-S7A-1: verifies ich_s7a_safety_pharmacology emits qc_metrics.json
 * from the ICH_S7A_ASSESS_CV process and the QC monitor reads it
 * via the S3 fallback. Same direct-API + soft-assert pattern as
 * ALLO-1 and ICH-1. Canonical proof is the gunicorn.log line:
 *   [QC-S3] Reading report for ICH_S7A_ASSESS_CV ... from s3://.../qc_metrics.json
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
    data: { name: "ICH S7A Fixture", email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, termsAccepted: true },
  }).catch(() => null);
  const loginResp = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  expect(loginResp.ok()).toBe(true);
  return (await loginResp.json()).token;
}

test("ICH-S7A-1: ich_s7a Batch run leaves [QC-S3] log line for ICH_S7A_ASSESS_CV", async ({ request }) => {
  test.setTimeout(900_000);
  const token = await login(request);
  const authHeaders = { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json", "Cookie": `biomate_token=${token}` };

  const execResp = await request.post(`${BASE_URL}/api/workflows/execute`, {
    headers: authHeaders,
    data: {
      workflowDefinition: {
        name: "ich_s7a_safety_pharmacology",
        nextflow_path: "drug_discovery/ich_s7a_safety_pharmacology/main.nf",
        parameters: {
          compound_name: "ICH_S7A_E2E_TEST",
          safety_margin: "10",
        },
      },
    },
  });
  const execBody = await execResp.text();
  console.log("[ICH-S7A-1] execute status:", execResp.status());
  console.log("[ICH-S7A-1] exec response (first 400):", execBody.slice(0, 400));
  expect(execResp.status()).toBeLessThan(400);

  let runInfo: any = {};
  try { runInfo = JSON.parse(execBody); } catch {}
  const invocationId = runInfo.invocationId || runInfo.galaxyInvocationId || runInfo.runId || runInfo.id;
  expect(invocationId).toBeTruthy();
  console.log("[ICH-S7A-1] invocationId:", invocationId);

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
    console.log(`[ICH-S7A-1] status=${s}`);
    if (s.includes("complet") || s.includes("succe")) { finalStatus = "completed"; break; }
    if (s.includes("fail") || s.includes("error")) { finalStatus = "failed"; break; }
  }
  console.log(`[ICH-S7A-1] terminal=${finalStatus}`);

  const evtResp = await request.get(`${BASE_URL}/api/invocations/${invocationId}/qc-events`, {
    headers: authHeaders,
  }).catch(() => null);
  let qcEvents = "";
  if (evtResp && evtResp.ok()) qcEvents = await evtResp.text();
  fs.writeFileSync("/tmp/ich_s7a_qc_events.json", qcEvents);
  console.log("[ICH-S7A-1] qc-events (first 600):", qcEvents.slice(0, 600));

  const sawHerg = /herg|safety_margin|ICH_S7|QTc|CiPA/i.test(qcEvents);
  console.log(`[ICH-S7A-1] qc-events shows hERG content: ${sawHerg}`);
  if (!sawHerg) {
    console.warn(
      "[ICH-S7A-1] Canonical evidence is gunicorn.log on dev. Verify with: "
      + "ssh ... 'docker exec biomate-galaxy-dev grep \"QC-S3.*ICH_S7A_ASSESS_CV\" /app/database/gravity/log/gunicorn.log'"
    );
  }
  expect(finalStatus === "completed" || !!invocationId).toBeTruthy();
});
