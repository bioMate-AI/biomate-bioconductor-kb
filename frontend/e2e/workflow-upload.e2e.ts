/**
 * E2E: Personal workflow upload via sidebar "Import Workflow" button.
 *
 * Covers:
 *  - Sidebar "Import Workflow" button opens the upload modal
 *  - Modal submit is disabled until a file is selected
 *  - Successful upload returns workflow_name + shows success state
 *  - GET /api/workflows/personal lists the newly uploaded workflow
 *  - Auth gates: 401 for unauthenticated requests
 *
 * Uses the canonical fixture account (CLAUDE.md §"E2E test user").
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const NF_STUB = [
  'nextflow.enable.dsl=2',
  '',
  'workflow {',
  "  Channel.of('Hello') | view { it + ' from E2E' }",
  '}',
].join('\n');

const GA_STUB = JSON.stringify({
  a_galaxy_workflow: "true",
  annotation: "E2E test workflow",
  format_version: "0.1",
  name: "E2E Galaxy Stub",
  steps: {},
  uuid: "00000000-e2e0-0000-0000-000000000001",
});

// Open the workflow upload surface via the CURRENT entry point:
// sidebar "Workflows" (button-workflows-nav) → WorkflowHistoryDialog → "Import Workflow" tab.
// (The old dedicated `button-import-workflow` was removed; the dialog's tab now owns upload.)
async function openUploadTab(page: import("@playwright/test").Page) {
  await page.goto(`${BASE_URL}/`);
  await page.getByTestId("button-workflows-nav").click();
  await expect(page.getByTestId("workflow-history-dialog")).toBeVisible({ timeout: 15000 });
  await page.getByTestId("tab-upload").click();
  await expect(page.getByTestId("workflow-upload-modal")).toBeVisible({ timeout: 5000 });
}

test.describe("workflow-upload", () => {
  test("sidebar Workflows → Import Workflow tab opens upload modal", async ({ page }) => {
    await loginAsFixture(page);
    await openUploadTab(page);
  });

  test("modal submit is disabled until a file is selected", async ({ page }) => {
    await loginAsFixture(page);
    await openUploadTab(page);

    // No file selected yet — submit button should be disabled
    await expect(page.getByTestId("workflow-upload-submit")).toBeDisabled();
  });

  test("upload .nf workflow succeeds and appears in personal list", async ({ page }) => {
    await loginAsFixture(page);
    await openUploadTab(page);

    await page.getByTestId("workflow-name-input").fill("E2E NF Stub");

    await page.getByTestId("workflow-file-input").setInputFiles({
      name: "e2e_stub.nf",
      mimeType: "text/plain",
      buffer: Buffer.from(NF_STUB),
    });

    await expect(page.getByTestId("workflow-upload-submit")).toBeEnabled({ timeout: 2000 });
    await page.getByTestId("workflow-upload-submit").click();

    // Success state: green check + workflow name visible
    await expect(
      page.locator(
        '[data-testid="workflow-upload-modal"] .text-green-700,' +
        '[data-testid="workflow-upload-modal"] .text-green-400'
      )
    ).toBeVisible({ timeout: 10000 });

    // Verify it appears in the personal list (page.request inherits auth cookies)
    const listResp = await page.request.get(`${BASE_URL}/api/workflows/personal`);
    expect(listResp.ok()).toBeTruthy();
    const workflows: any[] = await listResp.json();
    const uploaded = workflows.find((w: any) => w.workflow_name === "E2E NF Stub");
    expect(uploaded).toBeDefined();
    expect(uploaded.file_type).toBe("nf");
  });

  test("upload .ga Galaxy workflow is rejected (Nextflow-only import)", async ({ page }) => {
    await loginAsFixture(page);
    await openUploadTab(page);

    // accept= omits .ga; setInputFiles still assigns — UI client-side guard must reject.
    await page.getByTestId("workflow-file-input").setInputFiles({
      name: "e2e_stub.ga",
      mimeType: "application/json",
      buffer: Buffer.from(GA_STUB),
    });

    await expect(page.getByTestId("workflow-upload-modal")).toContainText(/cannot be imported|\.ga/i, {
      timeout: 5000,
    });
    await expect(page.getByTestId("workflow-upload-submit")).toBeDisabled();

    // Defense in depth: API also rejects even if the UI were bypassed.
    const apiResp = await page.request.post(`${BASE_URL}/api/workflows/upload-file`, {
      multipart: {
        file: { name: "e2e_stub.ga", mimeType: "application/json", buffer: Buffer.from(GA_STUB) },
        workflowName: "E2E Galaxy Stub Reject",
      },
    });
    expect(apiResp.status()).toBe(415);
    const body = await apiResp.json();
    expect(String(body.error || "")).toMatch(/\.ga|Nextflow/i);
  });

  test("GET /api/workflows/personal returns 401 when not authenticated", async ({ request }) => {
    const resp = await request.get(`${BASE_URL}/api/workflows/personal`);
    expect(resp.status()).toBe(401);
  });

  test("POST /api/workflows/upload-file returns 401 when not authenticated", async ({ request }) => {
    const resp = await request.post(`${BASE_URL}/api/workflows/upload-file`, {
      multipart: { file: { name: "test.nf", mimeType: "text/plain", buffer: Buffer.from(NF_STUB) } },
    });
    expect(resp.status()).toBe(401);
  });
});
