/**
 * E2E: Project creation, file upload/delete, and My Imports workflow management.
 *
 * UC-A  Project create → sidebar refresh → navigate to detail → files tab
 * UC-B  Project files: upload → tree shows inputs/ folder → delete → gone
 * UC-C  My Imports: upload workflow → row appears in tab → delete → gone
 * UC-D  Auth gates: project and file endpoints return 401 unauthenticated
 *
 * All tests use one canonical fixture account per CLAUDE.md §"E2E test user".
 * One project is created at the top and reused across file tests (CLAUDE.md
 * §"E2E plan discipline" rule 2).
 */
import { test, expect, type APIRequestContext } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

// S3 file operations only work when AWS credentials are configured in the environment.
// Tests that require S3 are skipped locally and run on the dev EC2 where credentials are set.
const S3_AVAILABLE = !!(process.env.AWS_ACCESS_KEY_ID && process.env.S3_BUCKET_NAME);

const NF_STUB = [
  "nextflow.enable.dsl=2",
  "",
  "workflow {",
  "  Channel.of('Hello') | view { it + ' from project E2E' }",
  "}",
].join("\n");

// Project created once; reused across all file tests.
let sharedProjectId: string | null = null;

async function createProject(request: APIRequestContext, name: string): Promise<string> {
  const res = await request.post(`${BASE_URL}/api/projects`, {
    data: { name, description: "E2E project for file tree testing", primaryDomain: "genomics" },
  });
  expect(res.ok(), `POST /api/projects failed: ${await res.text()}`).toBeTruthy();
  const body = await res.json();
  // API may return { project: { id } } or { id }
  const id = body?.project?.id ?? body?.id;
  expect(id, "project id missing from response").toBeTruthy();
  return id;
}

test.describe("project-files", () => {
  // ────────────────────────────────────────────────────────────────────────────
  // UC-D  Auth gates (no login needed)
  // ────────────────────────────────────────────────────────────────────────────
  test("GET /api/projects returns 401 when not authenticated", async ({ request }) => {
    const res = await request.get(`${BASE_URL}/api/projects`);
    expect(res.status()).toBe(401);
  });

  test("POST /api/projects returns 401 when not authenticated", async ({ request }) => {
    const res = await request.post(`${BASE_URL}/api/projects`, { data: { name: "x" } });
    expect(res.status()).toBe(401);
  });

  test("GET /api/projects/fake-id/files returns 401 when not authenticated", async ({ request }) => {
    const res = await request.get(`${BASE_URL}/api/projects/00000000-0000-0000-0000-000000000001/files`);
    expect(res.status()).toBe(401);
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-A  Project creation via API
  // ────────────────────────────────────────────────────────────────────────────
  test("POST /api/projects creates project and it appears in GET /api/projects list", async ({ page }) => {
    await loginAsFixture(page);

    const name = `E2E Files Project ${Date.now()}`;
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      data: { name, description: "E2E test", primaryDomain: "genomics" },
    });
    expect(res.ok(), `create failed: ${await res.text()}`).toBeTruthy();
    const body = await res.json();
    const id = body?.project?.id ?? body?.id;
    expect(id).toBeTruthy();
    sharedProjectId = id;

    // Verify it appears in the list
    const listRes = await page.request.get(`${BASE_URL}/api/projects`);
    expect(listRes.ok()).toBeTruthy();
    const listBody = await listRes.json();
    const projects: any[] = listBody?.projects ?? listBody ?? [];
    const found = projects.find((p: any) => p.id === id || p.name === name);
    expect(found, `project "${name}" not found in GET /api/projects list`).toBeTruthy();
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-A  Sidebar shows new project
  // ────────────────────────────────────────────────────────────────────────────
  test("sidebar Projects section shows newly created project", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Sidebar must be visible
    await expect(page.getByTestId("button-projects-section")).toBeVisible({ timeout: 10000 });

    // Expand projects if collapsed
    const projSection = page.getByTestId("button-projects-section");
    const isExpanded = await projSection.getAttribute("data-expanded").catch(() => null);
    if (isExpanded === "false") await projSection.click();

    // Create a project and reload the page
    const name = `Sidebar Test ${Date.now()}`;
    await page.request.post(`${BASE_URL}/api/projects`, { data: { name } });

    // Navigate to force sidebar refresh
    await page.goto(`${BASE_URL}/`);
    await expect(page.getByTestId("button-projects-section")).toBeVisible({ timeout: 10000 });

    // Project name should appear somewhere in the sidebar
    await expect(page.locator(`text=${name}`)).toBeVisible({ timeout: 8000 });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-B  Project file tree: upload → inputs/ folder → delete
  // ────────────────────────────────────────────────────────────────────────────
  test("project file upload appears in tree under inputs/ folder", async ({ page }) => {
    test.skip(!S3_AVAILABLE, "S3 not configured locally — run on dev EC2");
    await loginAsFixture(page);

    // Ensure we have a project to work with
    const projectId = sharedProjectId ?? await createProject(page.request, `E2E File Tree ${Date.now()}`);
    if (!sharedProjectId) sharedProjectId = projectId;

    // Navigate directly to the project files tab
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=files`);

    // File tree should render
    await expect(page.getByTestId("project-file-tree")).toBeVisible({ timeout: 12000 });

    // Click the Upload button in the toolbar
    const uploadBtn = page.getByTestId("project-files-upload-btn");
    await expect(uploadBtn).toBeVisible({ timeout: 8000 });

    // Set files via the hidden input
    const fileInput = page.getByTestId("project-files-input");
    await fileInput.setInputFiles({
      name: "e2e_sample.fastq",
      mimeType: "text/plain",
      buffer: Buffer.from("@SEQ_ID\nGATTTGGGGTTTCAAGCAGGGCGATTGCTT\n+\n!''*((((***+))%%%++)(%%%%).1***"),
    });

    // After upload, inputs/ folder should appear
    await expect(page.getByTestId("folder-inputs")).toBeVisible({ timeout: 10000 });

    // The filename should be visible somewhere in the tree
    await expect(page.locator("text=e2e_sample.fastq")).toBeVisible({ timeout: 5000 });
  });

  test("uploaded project file can be deleted", async ({ page }) => {
    test.skip(!S3_AVAILABLE, "S3 not configured locally — run on dev EC2");
    await loginAsFixture(page);

    // Upload a file directly via API for a clean state
    const projectId = sharedProjectId ?? await createProject(page.request, `E2E Del Test ${Date.now()}`);

    const form = new FormData();
    form.append("file", new Blob(["delete me"], { type: "text/plain" }), "to_delete.txt");
    const upRes = await page.request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
      multipart: { file: { name: "to_delete.txt", mimeType: "text/plain", buffer: Buffer.from("delete me") } },
    });
    expect(upRes.ok(), `upload failed: ${await upRes.text()}`).toBeTruthy();
    const fileBody = await upRes.json();
    const fileId = fileBody?.file?.id ?? fileBody?.id;
    expect(fileId).toBeTruthy();

    // Navigate to files tab
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=files`);
    await expect(page.getByTestId("project-file-tree")).toBeVisible({ timeout: 12000 });

    // Expand inputs/ folder
    await expect(page.getByTestId("folder-inputs")).toBeVisible({ timeout: 8000 });
    await page.getByTestId("folder-inputs").click();

    // Hover to reveal delete button and click it
    const deleteBtn = page.getByTestId(`file-delete-${fileId}`);
    await expect(deleteBtn).toBeVisible({ timeout: 5000 });

    // Accept the confirm dialog
    page.once("dialog", (dialog) => dialog.accept());
    await deleteBtn.click();

    // Verify gone from tree — backend DELETE called, file row removed
    await expect(page.locator("text=to_delete.txt")).not.toBeVisible({ timeout: 5000 });
  });

  test("GET /api/projects/:id/files lists files after upload", async ({ page }) => {
    test.skip(!S3_AVAILABLE, "S3 not configured locally — run on dev EC2");
    await loginAsFixture(page);
    const projectId = sharedProjectId ?? await createProject(page.request, `E2E API Test ${Date.now()}`);

    // Upload via API
    const upRes = await page.request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
      multipart: { file: { name: "api_test.txt", mimeType: "text/plain", buffer: Buffer.from("api test") } },
    });
    expect(upRes.ok()).toBeTruthy();

    // List via API
    const listRes = await page.request.get(`${BASE_URL}/api/projects/${projectId}/files`);
    expect(listRes.ok()).toBeTruthy();
    const data = await listRes.json();
    const files: any[] = data?.files ?? [];
    const found = files.find((f: any) => f.name === "api_test.txt");
    expect(found, "uploaded file not found in files list").toBeTruthy();
    expect(found.source).toBe("upload");
    expect(found.size).toBeGreaterThan(0);
  });

  test("GET /api/projects/:id/files/:id/url returns presigned URL", async ({ page }) => {
    test.skip(!S3_AVAILABLE, "S3 not configured locally — run on dev EC2");
    await loginAsFixture(page);
    const projectId = sharedProjectId ?? await createProject(page.request, `E2E URL Test ${Date.now()}`);

    const upRes = await page.request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
      multipart: { file: { name: "presign_test.txt", mimeType: "text/plain", buffer: Buffer.from("presign test") } },
    });
    expect(upRes.ok()).toBeTruthy();
    const fileId = (await upRes.json())?.file?.id;
    expect(fileId).toBeTruthy();

    const urlRes = await page.request.get(`${BASE_URL}/api/projects/${projectId}/files/${fileId}/url`);
    expect(urlRes.ok()).toBeTruthy();
    const { url, name } = await urlRes.json();
    expect(url).toBeTruthy();
    expect(typeof url).toBe("string");
    expect(name).toBe("presign_test.txt");
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-C  My Imports: upload → row visible → delete → gone
  // ────────────────────────────────────────────────────────────────────────────
  test("My Imports tab shows workflow after upload", async ({ page }) => {
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/`);

    // Open Workflows dialog on Import Workflow tab
    await page.getByTestId("button-import-workflow").click();
    await expect(page.getByTestId("workflow-upload-modal")).toBeVisible({ timeout: 8000 });

    // Upload a .nf workflow
    const wfName = `My Imports E2E ${Date.now()}`;
    await page.getByTestId("workflow-name-input").fill(wfName);
    await page.getByTestId("workflow-file-input").setInputFiles({
      name: "imports_test.nf",
      mimeType: "text/plain",
      buffer: Buffer.from(NF_STUB),
    });

    await expect(page.getByTestId("workflow-upload-submit")).toBeEnabled({ timeout: 3000 });
    await page.getByTestId("workflow-upload-submit").click();

    // Wait for success state (green check + workflow name in success div)
    await expect(
      page.locator('[data-testid="workflow-upload-modal"] .text-green-700, [data-testid="workflow-upload-modal"] .text-green-400')
    ).toBeVisible({ timeout: 10000 });

    // Click "View in My Imports" button from the success state — this calls
    // setActiveTab('imports') + fetchImports('') in the dialog.
    await page.getByRole("button", { name: /view in my imports/i }).click();

    // The workflow name should appear in the list
    await expect(page.locator(`text=${wfName}`)).toBeVisible({ timeout: 8000 });
  });

  test("My Imports: delete workflow removes it from the list", async ({ page }) => {
    await loginAsFixture(page);

    // Upload via API for a clean, known state
    const wfName = `Delete Me ${Date.now()}`;
    const upRes = await page.request.post(`${BASE_URL}/api/workflows/upload-file`, {
      multipart: {
        file: { name: "del_test.nf", mimeType: "text/plain", buffer: Buffer.from(NF_STUB) },
        workflowName: wfName,
      },
    });
    expect(upRes.ok(), `workflow upload failed: ${await upRes.text()}`).toBeTruthy();
    const upBody = await upRes.json();
    const wfId = upBody?.id ?? upBody?.workflow?.id;
    expect(wfId).toBeTruthy();

    // Navigate to My Imports tab
    await page.goto(`${BASE_URL}/`);
    await page.getByTestId("button-import-workflow").click();
    await expect(page.getByTestId("tab-my-imports")).toBeVisible({ timeout: 8000 });
    await page.getByTestId("tab-my-imports").click();

    // Workflow should be in the list
    await expect(page.locator(`text=${wfName}`)).toBeVisible({ timeout: 8000 });

    // Click delete button and confirm
    const deleteBtn = page.getByTestId(`button-delete-personal-${wfId}`);
    await expect(deleteBtn).toBeVisible({ timeout: 5000 });
    page.once("dialog", (d) => d.accept());
    await deleteBtn.click();

    // Verify the row is gone
    await expect(page.locator(`text=${wfName}`)).not.toBeVisible({ timeout: 5000 });

    // Verify via API too
    const listRes = await page.request.get(`${BASE_URL}/api/workflows/personal`);
    expect(listRes.ok()).toBeTruthy();
    const workflows = await listRes.json();
    const stillExists = workflows.find((w: any) => w.id === wfId);
    expect(stillExists, "workflow still exists in API after UI delete").toBeFalsy();
  });

  test("DELETE /api/workflows/personal/:id returns 401 when not authenticated", async ({ request }) => {
    const res = await request.delete(`${BASE_URL}/api/workflows/personal/00000000-0000-0000-0000-000000000001`);
    expect(res.status()).toBe(401);
  });
});
