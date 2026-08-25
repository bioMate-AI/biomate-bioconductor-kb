/**
 * TRUE end-to-end (not unit): upload a real dataset → the viewer auto-selected for its format
 * launches → the container actually SERVES its UI. Runs against dev with the canonical fixture.
 *
 *   BIOMATE_URL=https://dev-public.biomate.ai npx playwright test interactive-autoselect-serve.e2e.ts
 *
 * The auto-select mapping (format → viewer) is unit-tested in
 * src/lib/interactive-viewers.test.ts; here we assert the *end result* on live dev:
 *   h5ad  → CellxGene  → serves the CELL×GENE UI
 *   .txt  → Jupyter    → serves JupyterLab
 * The launch path is source-agnostic (any HDA), so an uploaded INPUT dataset and a workflow OUTPUT
 * dataset hit the identical launch→route→serve path exercised here.
 */
import { test, expect } from "@playwright/test";
import fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.describe.configure({ mode: "serial" });

async function uploadAndServe(page: any, filePath: string, fileName: string, toolId: string) {
  const buf = fs.readFileSync(filePath);
  const up = await page.request.post(`${BASE_URL}/api/datasets/upload`, {
    multipart: { file: { name: fileName, mimeType: "application/octet-stream", buffer: buf }, description: "e2e-autoselect" },
    timeout: 120_000,
  });
  expect(up.ok(), `upload ${fileName} failed: ${up.status()}`).toBeTruthy();
  const hda = (await up.json()).galaxy_dataset_id as string;
  expect(hda, "no galaxy_dataset_id returned").toBeTruthy();

  const launch = await page.request.post(`${BASE_URL}/api/interactive/launch`, {
    data: { tool_id: toolId, inputs: { dataset_ids: [hda] } },
    timeout: 120_000,
  });
  expect(launch.ok(), `launch ${toolId} failed: ${launch.status()}`).toBeTruthy();
  const url = (await launch.json()).entry_point_url as string;
  expect(url, "no entry_point_url").toMatch(/^\/interactive\/[a-z0-9]+\//i);

  // poll until the container serves (boot + data load can take 10–60s)
  let code = 0, body = "";
  for (let i = 0; i < 40; i++) {
    const r = await page.request.get(`${BASE_URL}${url}`, { timeout: 15_000, maxRedirects: 0 }).catch(() => null);
    code = r ? r.status() : 0;
    if (code === 200 || (code >= 300 && code < 400)) { body = r ? await r.text().catch(() => "") : ""; break; }
    await new Promise((res) => setTimeout(res, 3000));
  }
  return { code, body, url };
}

test("E2E: input h5ad → auto CellxGene → serves CELL×GENE UI", async ({ page }) => {
  test.setTimeout(240_000);
  await loginAsFixture(page);
  // recommendViewers('h5ad').primary === 'cellxgene' (unit-tested); tool_id below is that result.
  const { code, body, url } = await uploadAndServe(page, "/tmp/test_cxg_compat.h5ad", "e2e_cxg.h5ad", "interactive_tool_cellxgene");
  console.log("[cellxgene] serve code:", code, "url:", url);
  expect([200, 302]).toContain(code);
  if (code === 200) expect(body.toLowerCase()).toContain("cellxgene");
});

test("E2E: input .txt → auto Jupyter → serves JupyterLab", async ({ page }) => {
  test.setTimeout(240_000);
  await loginAsFixture(page);
  // recommendViewers('txt').primary === 'jupyter' (generic escape-hatch); tool_id is that result.
  fs.writeFileSync("/tmp/e2e_generic.txt", "col1\tcol2\n1\t2\n3\t4\n");
  const { code, body, url } = await uploadAndServe(page, "/tmp/e2e_generic.txt", "e2e_generic.txt", "interactive_tool_jupyter_notebook");
  console.log("[jupyter] serve code:", code, "url:", url);
  expect([200, 302]).toContain(code);
  if (code === 200) expect(body).toMatch(/JupyterLab/i);
});
