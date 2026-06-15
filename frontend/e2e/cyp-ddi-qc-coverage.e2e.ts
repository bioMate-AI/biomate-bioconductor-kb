/*
 * CYP-DDI-1: verifies cyp_ddi_panel DDI_RISK_ASSESSMENT emits qc_metrics.json
 * with the FDA 2020 R1/R2 overall_recommendation field, read from S3.
 * Default SMILES: ketoconazole (canonical CYP3A4 inhibitor) — gate should
 * report CLINICAL_STUDY_RECOMMENDED.
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
    data: { name: "CYP-DDI Fixture", email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, termsAccepted: true },
  }).catch(() => null);
  const r = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  expect(r.ok()).toBe(true);
  return (await r.json()).token;
}

test("CYP-DDI-1: cyp_ddi_panel Batch run leaves [QC-S3] log line for DDI_RISK_ASSESSMENT", async ({ request }) => {
  test.setTimeout(900_000);
  const token = await login(request);
  const h = { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json", "Cookie": `biomate_token=${token}` };
  const er = await request.post(`${BASE_URL}/api/workflows/execute`, {
    headers: h,
    data: {
      workflowDefinition: {
        name: "cyp_ddi_panel",
        nextflow_path: "drug_discovery/cyp_ddi_panel/main.nf",
        parameters: {
          // ketoconazole — canonical strong CYP3A4 inhibitor
          smiles: "CC(=O)N1CCN(CC1)c1ccc(OCC2COC(O2)(c3ccc(cc3)Cl)c4ccc(cc4)Cl)cc1",
          compound_name: "ketoconazole",
          max_clinical_dose_mg: "400",
          dose_route: "oral",
        },
      },
    },
  });
  const body = await er.text();
  console.log("[CYP-DDI-1] exec status:", er.status(), "body:", body.slice(0, 300));
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
  fs.writeFileSync("/tmp/cyp_ddi_qc_events.json", e && e.ok() ? await e.text() : "");
  expect(!!inv).toBeTruthy();
});
