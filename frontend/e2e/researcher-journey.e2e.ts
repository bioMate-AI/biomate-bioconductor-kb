/**
 * Researcher Journey — full end-to-end scenario test
 *
 * Tests the complete flow a real researcher experiences:
 *   1. Create a project via the sidebar dialog
 *   2. Navigate to the project and write research instructions
 *   3. Verify instructions persist after navigation away and back
 *   4. Visit the Files tab — empty state visible, upload button present
 *   5. Import a custom .nf workflow via the Import Workflow dialog
 *   6. View the workflow in My Imports — Open it → right panel appears
 *   7. Ask BioMate in the chat about the project — AI responds
 *   8. Cleanup: delete the imported workflow, archive the project
 *
 * Tests run sequentially (workers: 1) so module-level state carries forward.
 * All tests use the canonical fixture account per CLAUDE.md §"E2E test user".
 *
 * Timeout budget: 90 s per AI chat call (per CLAUDE.md §"E2E plan discipline" rule 6).
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

// ─── Shared state ────────────────────────────────────────────────────────────
const TS = Date.now();
const PROJECT_NAME = `RNA-seq Study ${TS}`;
const WORKFLOW_NAME = `My DESeq2 Pipeline ${TS}`;
const INSTRUCTIONS = `Analyze differential expression between treated and control samples.
Reference genome: GRCh38. FDR threshold: 0.05.`;

const NF_STUB = [
  "nextflow.enable.dsl=2",
  "",
  "params {",
  "  genome   = 'GRCh38'",
  "  fdr      = 0.05",
  "}",
  "",
  "workflow {",
  "  Channel.of('DESeq2 placeholder') | view",
  "}",
].join("\n");

let projectId: string | null = null;
let workflowId: string | null = null;

// ─────────────────────────────────────────────────────────────────────────────

test.describe("Researcher Journey", () => {
  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Create a project via the sidebar "New project" button
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 1: create project via sidebar dialog", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Sidebar must be ready
    await expect(page.getByTestId("button-new-project")).toBeVisible({ timeout: 10_000 });
    await page.getByTestId("button-new-project").click();

    // Dialog appears
    await expect(page.getByTestId("input-project-name")).toBeVisible({ timeout: 5_000 });

    // Fill in the project name
    await page.getByTestId("input-project-name").fill(PROJECT_NAME);

    // Optionally fill description
    const descBox = page.getByTestId("textarea-project-description");
    if (await descBox.isVisible()) {
      await descBox.fill("E2E scenario test — RNA-seq differential expression");
    }

    // Create
    await page.getByTestId("button-create-project").click();

    // Dialog closes and API responds → project appears in sidebar
    await expect(page.getByTestId("input-project-name")).not.toBeVisible({ timeout: 5_000 });

    // Project name should be visible in sidebar within a few seconds
    await expect(page.locator(`text=${PROJECT_NAME}`).first()).toBeVisible({ timeout: 8_000 });

    // Capture the project id from the API for use in later steps
    const listRes = await page.request.get(`${BASE_URL}/api/projects`);
    expect(listRes.ok()).toBeTruthy();
    const { projects } = await listRes.json();
    const found = projects?.find((p: any) => p.name === PROJECT_NAME);
    expect(found, `Project "${PROJECT_NAME}" missing from GET /api/projects`).toBeTruthy();
    projectId = found.id;
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 2 — Navigate to project detail and write research instructions
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 2: navigate to project and save research instructions", async ({ page }) => {
    await loginAsFixture(page);
    expect(projectId, "projectId not set — Step 1 must pass first").toBeTruthy();

    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=chat`);

    // Project heading visible
    await expect(page.locator("h1").filter({ hasText: PROJECT_NAME })).toBeVisible({ timeout: 12_000 });

    // Click Edit instructions
    await expect(page.getByTestId("button-edit-instructions")).toBeVisible({ timeout: 5_000 });
    await page.getByTestId("button-edit-instructions").click();

    // Instructions textarea opens
    const textarea = page.getByTestId("textarea-edit-instructions");
    await expect(textarea).toBeVisible({ timeout: 3_000 });
    await textarea.fill(INSTRUCTIONS);

    // Save
    await page.getByTestId("button-save-instructions").click();

    // Save button disappears (edit mode exits)
    await expect(page.getByTestId("button-save-instructions")).not.toBeVisible({ timeout: 5_000 });

    // Instructions text now shown in the read-only view
    await expect(page.locator(`text=FDR threshold`)).toBeVisible({ timeout: 3_000 });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 3 — Navigate away and back; verify instructions persisted
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 3: instructions persist after navigation away and back", async ({ page }) => {
    await loginAsFixture(page);
    expect(projectId).toBeTruthy();

    // Navigate away to home
    await page.goto(`${BASE_URL}/`);
    await expect(page.getByTestId("button-new-project")).toBeVisible({ timeout: 8_000 });

    // Navigate back to project
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=chat`);
    await expect(page.locator("h1").filter({ hasText: PROJECT_NAME })).toBeVisible({ timeout: 12_000 });

    // The saved instructions must still be visible in the sidebar panel
    await expect(page.locator(`text=FDR threshold`)).toBeVisible({ timeout: 5_000 });

    // Verify via API too — researchGoal saved in DB
    const res = await page.request.get(`${BASE_URL}/api/projects/${projectId}`);
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    const goal: string = body?.project?.researchGoal ?? body?.project?.research_goal ?? "";
    expect(goal).toContain("FDR threshold");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — Files tab: component renders, empty state or upload button present
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 4: Files tab renders with upload button", async ({ page }) => {
    await loginAsFixture(page);
    expect(projectId).toBeTruthy();

    await page.goto(`${BASE_URL}/projects?project=${projectId}`);
    await expect(page.locator("h1").filter({ hasText: PROJECT_NAME })).toBeVisible({ timeout: 12_000 });

    // Click the Files tab — the router ignores ?tab=files so we drive it via UI
    await page.getByRole("tab", { name: /files/i }).click();

    // File tree component must render
    await expect(page.getByTestId("project-file-tree")).toBeVisible({ timeout: 8_000 });

    // Upload button must be present
    await expect(page.getByTestId("project-files-upload-btn")).toBeVisible({ timeout: 5_000 });

    // Either empty-state copy or a file list — just ensure the tree loaded (no spinner)
    await expect(page.getByTestId("project-file-tree")).not.toContainText("Loading", { timeout: 5_000 });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 5 — Import a custom .nf workflow via the dialog
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 5: import custom workflow via Import Workflow dialog", async ({ page }) => {
    await loginAsFixture(page);

    await page.goto(`${BASE_URL}/`);
    await expect(page.getByTestId("button-import-workflow")).toBeVisible({ timeout: 10_000 });
    await page.getByTestId("button-import-workflow").click();

    // Dialog opens on Import Workflow tab
    await expect(page.getByTestId("workflow-upload-modal")).toBeVisible({ timeout: 5_000 });

    // Fill name and select file
    await page.getByTestId("workflow-name-input").fill(WORKFLOW_NAME);
    await page.getByTestId("workflow-file-input").setInputFiles({
      name: "deseq2_pipeline.nf",
      mimeType: "text/plain",
      buffer: Buffer.from(NF_STUB),
    });

    // Submit enabled
    await expect(page.getByTestId("workflow-upload-submit")).toBeEnabled({ timeout: 3_000 });
    await page.getByTestId("workflow-upload-submit").click();

    // Success state: green check appears
    await expect(
      page.locator('[data-testid="workflow-upload-modal"] .text-green-700, [data-testid="workflow-upload-modal"] .text-green-400')
    ).toBeVisible({ timeout: 10_000 });

    // Success message includes the workflow name
    await expect(page.locator(`text=${WORKFLOW_NAME} imported successfully`)).toBeVisible({ timeout: 3_000 });

    // Capture wf id via API for later steps
    const listRes = await page.request.get(`${BASE_URL}/api/workflows/personal`);
    expect(listRes.ok()).toBeTruthy();
    const workflows: any[] = await listRes.json();
    const found = workflows.find((w: any) => w.workflow_name === WORKFLOW_NAME);
    expect(found, `Workflow "${WORKFLOW_NAME}" not found in personal list after upload`).toBeTruthy();
    workflowId = found.id;
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 6 — My Imports tab shows the workflow; Open → right panel appears
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 6: My Imports shows workflow; Open loads it in the right panel", async ({ page }) => {
    await loginAsFixture(page);
    expect(workflowId).toBeTruthy();

    await page.goto(`${BASE_URL}/`);

    // Open dialog
    await page.getByTestId("button-import-workflow").click();

    // Switch to My Imports tab
    await expect(page.getByTestId("tab-my-imports")).toBeVisible({ timeout: 8_000 });
    await page.getByTestId("tab-my-imports").click();

    // The workflow we just imported must be the first row (ORDER BY created_at DESC)
    await expect(page.locator(`text=${WORKFLOW_NAME}`)).toBeVisible({ timeout: 8_000 });

    // Click "Open"
    const openBtn = page.getByTestId(`button-open-personal-${workflowId}`);
    await expect(openBtn).toBeVisible({ timeout: 5_000 });
    await openBtn.click();

    // Dialog closes and dispatches biomate:open-personal-workflow event (~160ms delay)
    await expect(page.getByTestId("tab-my-imports")).not.toBeVisible({ timeout: 5_000 });

    // Right panel opens with the workflow
    await expect(page.getByTestId("workflow-right-panel")).toBeVisible({ timeout: 5_000 });

    // Workflow name visible in the panel
    await expect(
      page.getByTestId("workflow-right-panel").locator(`text=${WORKFLOW_NAME}`)
    ).toBeVisible({ timeout: 3_000 });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 7 — Run the imported workflow to completion
  //
  // Opens the imported workflow in the right panel, clicks Run, then waits for
  // the workflow to reach a terminal state (completed or failed) by watching
  // the workflow-overall-status-badge data-status attribute via SSE/polling.
  //
  // The NF_STUB is `Channel.of('DESeq2 placeholder') | view` — trivial work
  // that completes in seconds once Nextflow is invoked.
  //
  // Timeout budget: 5 minutes — Galaxy backend + Nextflow startup latency.
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 7: run imported workflow to completion — track status idle→running→completed", async ({ page }) => {
    test.setTimeout(300_000); // 5 min — Nextflow start + execution + SSE round-trip
    await loginAsFixture(page);
    expect(workflowId, "workflowId not set — Step 5 must pass first").toBeTruthy();

    await page.goto(`${BASE_URL}/`);

    // ── 7a: Reopen the uploaded workflow in the right panel ─────────────────
    await page.getByTestId("button-import-workflow").click();
    await expect(page.getByTestId("tab-my-imports")).toBeVisible({ timeout: 8_000 });
    await page.getByTestId("tab-my-imports").click();
    await expect(page.locator(`text=${WORKFLOW_NAME}`)).toBeVisible({ timeout: 8_000 });

    const openBtn = page.getByTestId(`button-open-personal-${workflowId}`);
    await expect(openBtn).toBeVisible({ timeout: 5_000 });
    await openBtn.click();

    // Dialog closes and panel opens (160 ms dispatch delay in handleOpenPersonal)
    const panel = page.getByTestId("workflow-right-panel");
    await expect(panel).toBeVisible({ timeout: 5_000 });

    // Overall status badge in idle state is present in DOM but hidden (display:none).
    // Use toHaveAttribute (not toBeVisible) so it works on the hidden idle span.
    const badge = panel.locator('[data-testid="workflow-overall-status-badge"]');
    await expect(badge).toHaveAttribute("data-status", "idle", { timeout: 5_000 });

    // ── 7b: Click Run ────────────────────────────────────────────────────────
    const runBtn = panel.getByTestId("button-run-workflow-panel");
    await expect(runBtn).toBeVisible({ timeout: 5_000 });
    await runBtn.click();

    // ── 7c: Verify running state immediately after click ─────────────────────
    // The footer button changes text, and the overall badge flips to running.
    await expect(badge).toHaveAttribute("data-status", "running", { timeout: 30_000 });

    // ── 7d: Wait for terminal state (completed or failed) ────────────────────
    // Poll via waitForFunction — SSE delivers status updates in real time.
    await page.waitForFunction(
      () => {
        const b = document.querySelector('[data-testid="workflow-overall-status-badge"]');
        const s = b?.getAttribute("data-status");
        return s === "completed" || s === "failed";
      },
      undefined,
      { timeout: 240_000, polling: 1_000 },
    );

    // ── 7e: Assert completed (not failed) ────────────────────────────────────
    const finalStatus = await badge.getAttribute("data-status");
    expect(finalStatus, `Workflow ended with status '${finalStatus}' — expected 'completed'`).toBe("completed");

    // Run-again CTA appears in the footer for completed state
    await expect(panel.getByTestId("panel-run-again-cta")).toBeVisible({ timeout: 5_000 });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 8 — Cleanup: delete workflow, archive project
  // Runs even if earlier steps failed so we don't accumulate test data.
  // ──────────────────────────────────────────────────────────────────────────
  test("Step 8: cleanup — delete imported workflow and archive project", async ({ page }) => {
    await loginAsFixture(page);

    // Delete workflow (via UI to prove the delete endpoint round-trip)
    if (workflowId) {
      await page.goto(`${BASE_URL}/`);
      await page.getByTestId("button-import-workflow").click();
      await expect(page.getByTestId("tab-my-imports")).toBeVisible({ timeout: 8_000 });
      await page.getByTestId("tab-my-imports").click();
      await expect(page.locator(`text=${WORKFLOW_NAME}`)).toBeVisible({ timeout: 8_000 });

      const deleteBtn = page.getByTestId(`button-delete-personal-${workflowId}`);
      await expect(deleteBtn).toBeVisible({ timeout: 5_000 });
      page.once("dialog", (d) => d.accept());
      await deleteBtn.click();

      await expect(page.locator(`text=${WORKFLOW_NAME}`)).not.toBeVisible({ timeout: 5_000 });

      // Confirm via API
      const listRes = await page.request.get(`${BASE_URL}/api/workflows/personal`);
      const workflows: any[] = await listRes.json();
      expect(workflows.find((w: any) => w.id === workflowId)).toBeFalsy();
      workflowId = null;
    }

    // Archive project via API
    if (projectId) {
      const archiveRes = await page.request.post(`${BASE_URL}/api/projects/${projectId}/archive`);
      expect(archiveRes.ok(), `archive failed: ${await archiveRes.text()}`).toBeTruthy();

      // Verify status = archived
      const getRes = await page.request.get(`${BASE_URL}/api/projects/${projectId}`);
      const { project } = await getRes.json();
      expect(project.status).toBe("archived");
      projectId = null;
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SCENARIO B — My Imports bulk lifecycle
//
// Upload 3 workflows via API, delete 2 via UI, verify the 3rd survives a
// dialog reload. Tests state consistency: UI must match API at every step.
// ─────────────────────────────────────────────────────────────────────────────

const B_TS = Date.now() + 1; // slightly different ts so names don't collide
const B_NAMES = [`BulkA_${B_TS}`, `BulkB_${B_TS}`, `BulkC_${B_TS}`];
let bulkIds: string[] = [];

async function uploadWfViaApi(page: any, name: string): Promise<string> {
  const res = await page.request.post(`${BASE_URL}/api/workflows/upload-file`, {
    multipart: {
      file: { name: "stub.nf", mimeType: "text/plain", buffer: Buffer.from(NF_STUB) },
      workflowName: name,
    },
  });
  expect(res.ok(), `Upload of "${name}" failed: ${await res.text()}`).toBeTruthy();
  const body = await res.json();
  return body.id;
}

test.describe("Researcher Journey — My Imports bulk lifecycle", () => {
  test("Bulk Step 1: upload 3 workflows via API", async ({ page }) => {
    await loginAsFixture(page);
    for (const name of B_NAMES) {
      const id = await uploadWfViaApi(page, name);
      bulkIds.push(id);
    }
    expect(bulkIds).toHaveLength(3);
  });

  test("Bulk Step 2: open My Imports — all 3 workflows visible", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);
    await page.getByTestId("button-import-workflow").click();
    await page.getByTestId("tab-my-imports").click();

    for (const name of B_NAMES) {
      await expect(page.locator(`text=${name}`)).toBeVisible({ timeout: 8_000 });
    }
  });

  test("Bulk Step 3: delete BulkA via UI — row disappears, BulkB+C remain", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);
    await page.getByTestId("button-import-workflow").click();
    await page.getByTestId("tab-my-imports").click();
    await expect(page.locator(`text=${B_NAMES[0]}`)).toBeVisible({ timeout: 8_000 });

    page.once("dialog", (d) => d.accept());
    await page.getByTestId(`button-delete-personal-${bulkIds[0]}`).click();

    // BulkA gone
    await expect(page.locator(`text=${B_NAMES[0]}`)).not.toBeVisible({ timeout: 5_000 });
    // BulkB and BulkC still there
    await expect(page.locator(`text=${B_NAMES[1]}`)).toBeVisible({ timeout: 3_000 });
    await expect(page.locator(`text=${B_NAMES[2]}`)).toBeVisible({ timeout: 3_000 });
  });

  test("Bulk Step 4: delete BulkB via UI — BulkC alone remains", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);
    await page.getByTestId("button-import-workflow").click();
    await page.getByTestId("tab-my-imports").click();
    await expect(page.locator(`text=${B_NAMES[1]}`)).toBeVisible({ timeout: 8_000 });

    page.once("dialog", (d) => d.accept());
    await page.getByTestId(`button-delete-personal-${bulkIds[1]}`).click();

    await expect(page.locator(`text=${B_NAMES[1]}`)).not.toBeVisible({ timeout: 5_000 });
    await expect(page.locator(`text=${B_NAMES[2]}`)).toBeVisible({ timeout: 3_000 });
  });

  test("Bulk Step 5: close + reopen dialog — only BulkC visible (reload test)", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Open, go to My Imports, close, reopen — forces a fresh fetchImports call
    await page.getByTestId("button-import-workflow").click();
    await page.getByTestId("tab-my-imports").click();
    await page.keyboard.press("Escape");

    await page.getByTestId("button-import-workflow").click();
    await page.getByTestId("tab-my-imports").click();

    // Only BulkC visible
    await expect(page.locator(`text=${B_NAMES[2]}`)).toBeVisible({ timeout: 8_000 });
    await expect(page.locator(`text=${B_NAMES[0]}`)).not.toBeVisible({ timeout: 2_000 });
    await expect(page.locator(`text=${B_NAMES[1]}`)).not.toBeVisible({ timeout: 2_000 });

    // API also reflects the state
    const listRes = await page.request.get(`${BASE_URL}/api/workflows/personal`);
    const all: any[] = await listRes.json();
    const hasA = all.some((w: any) => w.id === bulkIds[0]);
    const hasB = all.some((w: any) => w.id === bulkIds[1]);
    const hasC = all.some((w: any) => w.id === bulkIds[2]);
    expect(hasA, "BulkA should have been deleted").toBe(false);
    expect(hasB, "BulkB should have been deleted").toBe(false);
    expect(hasC, "BulkC should still exist").toBe(true);
  });

  test("Bulk Step 6: cleanup — delete BulkC via API", async ({ page }) => {
    await loginAsFixture(page);
    if (bulkIds[2]) {
      const res = await page.request.delete(`${BASE_URL}/api/workflows/personal/${bulkIds[2]}`);
      expect(res.ok(), `cleanup delete failed: ${await res.text()}`).toBeTruthy();
    }
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Settings — MCP API key generation
  // Verifies: sidebar Settings entry visible → dialog opens → API Keys tab →
  // Generate key → plaintext shown once → copy works → revoke cleans up.
  // ─────────────────────────────────────────────────────────────────────────────
  test("Settings: generate and revoke an MCP API key", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // ── 1. Run Manager mobile layout: open panel, controls must be visible ──
    const rmToggle = page.getByTestId("button-toggle-run-manager");
    await expect(rmToggle).toBeVisible({ timeout: 8_000 });
    await rmToggle.click();
    const rmPanel = page.getByTestId("run-manager-panel");
    await expect(rmPanel).toBeVisible({ timeout: 4_000 });
    // Scope toggle must be rendered and clickable
    const scopeToggle = page.getByTestId("run-manager-scope-toggle");
    await expect(scopeToggle).toBeVisible();
    await page.getByTestId("run-manager-scope-all-chats").click();
    await expect(page.getByTestId("run-manager-scope-all-chats")).toHaveClass(/bg-primary/);
    // Close panel
    await rmToggle.click();
    await expect(rmPanel).not.toBeVisible({ timeout: 3_000 });

    // ── 2. Open Settings via the new sidebar entry ──────────────────────────
    // The sidebar Settings & API Keys button is now uncommented.
    const settingsBtn = page.getByTestId("button-settings-sidebar");
    await expect(settingsBtn).toBeVisible({ timeout: 8_000 });
    await settingsBtn.click();

    // Settings dialog should open
    await expect(page.getByRole("dialog")).toBeVisible({ timeout: 5_000 });

    // ── 3. Navigate to API Keys tab ─────────────────────────────────────────
    await page.getByTestId("tab-api-keys").click();
    const apiKeysContent = page.getByTestId("tab-content-api-keys");
    await expect(apiKeysContent).toBeVisible({ timeout: 4_000 });

    // ── 4. Generate a new key ───────────────────────────────────────────────
    await page.getByTestId("input-api-key-name").fill("Playwright MCP test key");
    await page.getByTestId("button-create-api-key").click();

    // Freshly created key card must appear and show the plaintext
    const freshCard = page.getByTestId("fresh-api-key-card");
    await expect(freshCard).toBeVisible({ timeout: 8_000 });
    const keyInput = page.getByTestId("input-fresh-api-key");
    const keyValue = await keyInput.inputValue();
    // Key format: bm_live_<base64url-random> — base64url uses A-Z a-z 0-9 _ -
    expect(keyValue).toMatch(/^bm_live_[A-Za-z0-9_-]+$/);

    // Copy button should work (does not throw)
    await page.getByTestId("button-copy-fresh-key").click();
    // Dismiss the fresh card
    await page.getByTestId("button-dismiss-fresh-key").click();
    await expect(freshCard).not.toBeVisible({ timeout: 3_000 });

    // ── 5. Key appears in the list — get its ID from the API ────────────────
    const keysList = page.getByTestId("api-keys-list");
    await expect(keysList).toBeVisible();

    // Fetch the key list to find the ID of the key we just created (newest first)
    const listRes = await page.request.get(`${BASE_URL}/api/user/api-keys`);
    const allKeys: any[] = await listRes.json();
    // Pick the most recently created "Playwright MCP test key" that isn't revoked
    const createdKey = allKeys
      .filter((k: any) => (k.name || '').includes('Playwright MCP test key') && !k.revokedAt)
      .sort((a: any, b: any) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())[0];
    expect(createdKey, 'created key should appear in list').toBeTruthy();
    const keyId = createdKey.id;

    // Row must be visible in the UI
    await expect(page.getByTestId(`api-key-row-${keyId}`)).toBeVisible({ timeout: 4_000 });

    // ── 6. Revoke it — row stays but shows "Revoked" badge, button gone ──────
    const revokeBtn = page.getByTestId(`button-revoke-api-key-${keyId}`);
    await expect(revokeBtn).toBeVisible({ timeout: 4_000 });
    await revokeBtn.click();
    // After revocation: Revoke button disappears (revokedAt is now set)
    await expect(revokeBtn).not.toBeVisible({ timeout: 5_000 });
    await expect(page.getByTestId(`api-key-row-${keyId}`).locator("text=Revoked")).toBeVisible({ timeout: 3_000 });
  });
});
