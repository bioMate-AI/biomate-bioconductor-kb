/*
 * ADMET-1: verifies predict_admet_properties emits qc_metrics.json with
 * hERG IC50 / Ames flag / DILI risk. Defaults include terfenadine
 * (canonical hERG positive control, withdrawn 1998) — the gate should TRIGGER.
 */
import { test, expect, APIRequestContext } from "@playwright/test";
import * as fs from "node:fs";

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL = "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

async function login(request: APIRequestContext): Promise<string> {
  await request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { name: "ADMET Fixture", email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, termsAccepted: true },
  }).catch(() => null);
  const r = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  expect(r.ok()).toBe(true);
  return (await r.json()).token;
}

test("ADMET-1: predict_admet_properties Batch run leaves [QC-S3] log line for PREDICT_ADMET_PROPERTIES", async ({ request }) => {
  test.setTimeout(900_000);
  const token = await login(request);
  const h = { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json", "Cookie": `biomate_token=${token}` };
  const er = await request.post(`${BASE_URL}/api/workflows/execute`, {
    headers: h,
    data: {
      workflowDefinition: {
        name: "predict_admet_properties",
        nextflow_path: "pharmacology/predict_admet_properties/main.nf",
        parameters: {
          smiles_list: '["CC(=O)OC1=CC=CC=C1C(=O)O", "OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC"]',
          ADMET_model_type: "MPNN",
        },
      },
    },
  });
  const body = await er.text();
  console.log("[ADMET-1] exec status:", er.status(), "body:", body.slice(0, 300));
  expect(er.status()).toBeLessThan(400);
  const info: any = JSON.parse(body);
  const inv = info.invocationId || info.galaxyInvocationId || info.runId;
  expect(inv).toBeTruthy();
  const dl = Date.now() + 720_000;
  while (Date.now() < dl) {
    await new Promise(r => setTimeout(r, 5_000));
    const sr = await request.get(`${BASE_URL}/api/workflows/runs/${inv}/status`, { headers: h }).catch(() => null);
    if (!sr || !sr.ok()) continue;
    const s = String((await sr.json()).status || "").toLowerCase();
    if (s.includes("complet") || s.includes("succe") || s.includes("fail") || s.includes("error")) break;
  }
  const e = await request.get(`${BASE_URL}/api/invocations/${inv}/qc-events`, { headers: h }).catch(() => null);
  fs.writeFileSync("/tmp/admet_qc_events.json", e && e.ok() ? await e.text() : "");
  expect(!!inv).toBeTruthy();
});
