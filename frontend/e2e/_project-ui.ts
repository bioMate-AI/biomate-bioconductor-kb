/**
 * Shared project helpers for the dataset-panel e2e harnesses (2026-11-12 audit, "Test quality").
 *
 * - createProject / deleteProjectLoudly: one project per harness; cleanup is retried and a final
 *   failure is a soft assertion + annotation (the test FAILS, and an earlier error is not masked)
 *   instead of a swallowed `.catch(() => {})` that silently leaks rows on the shared fixture.
 * - openProjectFiles / revealFile / openFile: deterministic navigation. Folder rows are TOGGLES, so
 *   we never click one "to be safe": wait for the tree, read the folder's real expanded state
 *   (aria-expanded when present, else whether its children are rendered — they render in the same
 *   commit as the row), and click only when the target is hidden because the folder is collapsed.
 *
 * All API calls go through the page's own APIRequestContext (cookie session from loginAsFixture).
 */
import { expect, test, type APIRequestContext, type Page } from "@playwright/test";
import { BASE_URL } from "./_fixture-login";

export async function createProject(api: APIRequestContext, name: string): Promise<string> {
  const res = await api.post(`${BASE_URL}/api/projects`, { data: { name } });
  expect(res.ok(), `create project ${res.status()} ${await res.text().catch(() => "")}`).toBeTruthy();
  const j = await res.json();
  const id = j.id || j.project?.id;
  expect(id, "project id").toBeTruthy();
  return id as string;
}

/**
 * Delete the harness project; retry transient failures; if it stays, FAIL: in a test body a soft
 * assertion (+ annotation) so an earlier error is not masked; in an afterAll hook pass
 * `{ inHook: true }` to throw (reported as a hook error).
 */
export async function deleteProjectLoudly(
  api: APIRequestContext, projectId: string | undefined, opts: { inHook?: boolean } = {},
): Promise<void> {
  if (!projectId) return;
  let last = "";
  for (let attempt = 1; attempt <= 3; attempt++) {
    const res = await api.delete(`${BASE_URL}/api/projects/${projectId}`).catch((e) => e as Error);
    if (!(res instanceof Error) && (res.ok() || res.status() === 404)) return;
    last = res instanceof Error ? `network error: ${res.message}` : `HTTP ${res.status()} ${await res.text().catch(() => "")}`;
    if (!(res instanceof Error) && res.status() < 500) break;   // a 4xx will not change on retry
    await new Promise((r) => setTimeout(r, 2000 * attempt));    // backoff before retrying a 5xx/network blip
  }
  const msg = `cleanup: project ${projectId} NOT deleted (${last}) — delete it manually`;
  if (opts.inHook) throw new Error(msg);
  test.info().annotations.push({ type: "cleanup-failed", description: msg });
  expect.soft(false, msg).toBe(true);
}

/** Upload one file (multipart; relativePath first keeps folders). Retries a bare gateway 5xx. */
export async function uploadFile(
  api: APIRequestContext, projectId: string, name: string, buffer: Buffer, mimeType: string, relativePath?: string,
): Promise<{ id: string; name: string; deduplicated: boolean; attempts: number[] }> {
  const multipart: Record<string, any> = {};
  if (relativePath) multipart.relativePath = relativePath;
  multipart.file = { name, mimeType, buffer };
  const attempts: number[] = [];
  let res = await api.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, { multipart, timeout: 120_000 });
  attempts.push(res.status());
  // dev has no retry layer: an empty-bodied 502/503/504 is a client↔EC2 blip, not the route.
  while ([502, 503, 504].includes(res.status()) && attempts.length < 3) {
    await new Promise((r) => setTimeout(r, 3000));
    res = await api.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, { multipart, timeout: 120_000 });
    attempts.push(res.status());
  }
  const body = await res.json().catch(() => ({}));
  expect(res.ok(), `upload ${relativePath || name} ${res.status()} ${JSON.stringify(body).slice(0, 200)}`).toBeTruthy();
  return { id: body.file.id, name: body.file.name, deduplicated: !!body.deduplicated, attempts };
}

/** Current bytes of a project file, fetched the way the browser does (presigned URL, no extra auth). */
export async function fileText(api: APIRequestContext, projectId: string, fileId: string): Promise<string> {
  const u = await api.get(`${BASE_URL}/api/projects/${projectId}/files/${fileId}/url`);
  expect(u.ok(), `file url ${u.status()}`).toBeTruthy();
  const { url } = await u.json();
  const res = await api.get(url.startsWith("http") ? url : `${BASE_URL}${url}`);
  expect(res.ok(), `download ${res.status()} ${(await res.text().catch(() => "")).slice(0, 200)}`).toBeTruthy();
  return res.text();
}

/** Data hub (/files) with this project active and its file tree rendered. */
export async function openProjectFiles(page: Page, projectId: string, projectName: string): Promise<void> {
  await page.goto(`${BASE_URL}/files`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  const pick = page.getByTestId(`data-hub-project-${projectId}`);
  const panes = page.getByTestId("data-hub-panes");
  await expect(pick.or(panes)).toBeVisible({ timeout: 60_000 });
  if (await panes.isVisible()) {
    // A project was already active (remembered). Switch only if it is not ours.
    if ((await page.getByTestId("data-hub-title").innerText()).trim() !== projectName) {
      await page.getByTestId("data-hub-change-project").click();
      await pick.click();
    }
  } else {
    await pick.click();
  }
  await expect(page.getByTestId("data-hub-title")).toHaveText(projectName, { timeout: 30_000 });
  await expect(page.getByTestId("project-file-tree").first()).toBeVisible({ timeout: 60_000 });
}

async function folderExpanded(page: Page, path: string): Promise<boolean> {
  return page.getByTestId(`folder-${path}`).evaluate((btn) => {
    const a = btn.getAttribute("aria-expanded");
    if (a !== null) return a === "true";
    // FolderRow is <div.group><button/>…</div> inside the node's wrapper <div>; children render
    // as siblings of that row only while the folder is open.
    const wrapper = btn.parentElement?.parentElement;
    return !!wrapper && wrapper.children.length > 1;
  });
}

/**
 * Make `file-open-<fileId>` visible: expand exactly the collapsed folders on its path.
 * `root` is the top-level folder path ("inputs", or "outputs/analysis" for run_code files);
 * `folder` the sub-folder under it ("pairs", "a/b").
 */
export async function revealFile(page: Page, fileId: string, folder?: string, root = "inputs"): Promise<void> {
  const open = page.getByTestId(`file-open-${fileId}`);
  const chain = [root, ...(folder ? folder.split("/").map((_, i, a) => `${root}/${a.slice(0, i + 1).join("/")}`) : [])];
  for (const p of chain) {
    const row = page.getByTestId(`folder-${p}`);
    await expect(row).toBeVisible({ timeout: 60_000 });
    if (!(await folderExpanded(page, p))) {
      await row.click();
      await expect.poll(() => folderExpanded(page, p), { message: `folder ${p} expands`, timeout: 10_000 }).toBe(true);
    }
  }
  await expect(open, `file ${fileId} listed under ${chain[chain.length - 1]}`).toBeVisible({ timeout: 30_000 });
}

/** Open a file as a dataset object and wait until that object (by name) is shown. */
export async function openFile(page: Page, fileId: string, baseName: string, folder?: string): Promise<void> {
  await revealFile(page, fileId, folder);
  await page.getByTestId(`file-open-${fileId}`).click();
  await expect(page.getByTestId("dataset-object-name")).toContainText(baseName, { timeout: 30_000 });
}

/**
 * Sidebar: show this project's children (New Chat / Files links). The PROJECTS section starts
 * expanded and is not toggled here; the project row IS a toggle, so it is clicked only while its
 * children are hidden.
 */
export async function expandProjectInSidebar(page: Page, projectId: string): Promise<void> {
  const projBtn = page.getByTestId(`button-project-${projectId}`);
  const newChat = page.getByTestId(`project-new-chat-${projectId}`);
  await expect(projBtn).toBeVisible({ timeout: 30_000 });
  if (!(await newChat.isVisible())) await projBtn.click();
  await expect(newChat).toBeVisible({ timeout: 15_000 });
}
