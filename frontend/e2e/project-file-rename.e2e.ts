/**
 * E2E: rename / move project files and folders in the project file tree (2026-11-11).
 *
 * One flow, one login, one project (deleted in `finally`) — CLAUDE.md §"E2E plan discipline":
 *   1. upload x/a.csv (API), then a second version of it (same name, new bytes → v2);
 *   2. UI: rename / move x/a.csv → y/b.csv (inline editor, Enter);
 *      verify tree (inputs/y/b.csv, no inputs/x), same id + s3_key, download = v2 bytes,
 *      version history still v2 + v1, diff + restore work by file id;
 *   3. an edit after the rename writes its new version under the NEW name's key;
 *   4. uploading a new x/a.csv creates a separate file at a fresh key — the renamed
 *      file's bytes (still at …/inputs/x/a.csv) are not overwritten;
 *   5. UI: rename folder y → z; tree shows inputs/z/b.csv;
 *   6. collisions: PATCH onto an existing name → 409 (UI shows the clash; nothing changes);
 *      a folder move that would clash → 409, all-or-nothing.
 * No mocks — live server. Coverage notes: the name rules (.., control chars, depth,
 * file/folder clashes) are unit-tested in server/project-file-rename.test.ts; the editor
 * key handling in client/src/components/project-file-tree.rename.test.tsx.
 */
import { test, expect, type APIRequestContext } from "@playwright/test";
import { request as pwRequest } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const V1 = "id,value\n1,10\n2,20\n";
const V2 = "id,value\n1,11\n2,20\n";
const OTHER = "id,value\n9,99\n";

async function upload(request: APIRequestContext, projectId: string, rel: string, body: string) {
  const res = await request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
    multipart: {
      relativePath: rel,
      file: { name: rel.split("/").pop()!, mimeType: "text/csv", buffer: Buffer.from(body) },
    },
  });
  expect(res.ok(), `upload ${rel} failed (${res.status()}): ${await res.text()}`).toBeTruthy();
  return (await res.json()).file as { id: string; name: string; s3_key: string };
}

async function listFiles(request: APIRequestContext, projectId: string): Promise<any[]> {
  const res = await request.get(`${BASE_URL}/api/projects/${projectId}/files`);
  expect(res.ok()).toBeTruthy();
  return (await res.json()).files ?? [];
}

async function download(request: APIRequestContext, projectId: string, fileId: string): Promise<string> {
  const res = await request.get(`${BASE_URL}/api/projects/${projectId}/files/${fileId}/url`);
  expect(res.ok(), `url failed: ${await res.text()}`).toBeTruthy();
  const { url } = await res.json();
  // A presigned S3 URL is fetched WITHOUT our auth headers, as a browser does: loginAsFixture puts a
  // Bearer token on every request of this context, and S3 rejects a second auth mechanism (400).
  let bytes;
  if (url.startsWith("/")) bytes = await request.get(`${BASE_URL}${url}`);
  else { const clean = await pwRequest.newContext(); bytes = await clean.get(url); }
  expect(bytes.ok(), `download failed (${bytes.status()})`).toBeTruthy();
  return bytes.text();
}

test.describe("project file rename / move", () => {
  test.setTimeout(180_000);

  test("rename + move a file and a folder; bytes, versions and collisions hold", async ({ page }) => {
    await loginAsFixture(page);
    const request = page.request;
    const created = await request.post(`${BASE_URL}/api/projects`, {
      data: { name: `E2E rename ${Date.now()}`, description: "file rename/move e2e" },
    });
    expect(created.ok(), `create project failed: ${await created.text()}`).toBeTruthy();
    const cj = await created.json();
    const projectId: string = cj?.project?.id ?? cj?.id;
    expect(projectId).toBeTruthy();

    try {
      // 1. x/a.csv, v1 then v2 (same name, new bytes → a new version of the same file)
      const a1 = await upload(request, projectId, "x/a.csv", V1);
      expect(a1.name).toBe("x/a.csv");
      const a2 = await upload(request, projectId, "x/a.csv", V2);
      expect(a2.id).toBe(a1.id);
      const keyBefore = (await listFiles(request, projectId)).find((f) => f.id === a1.id).s3_key;

      // 2. UI rename / move x/a.csv → y/b.csv
      await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=files`);
      await expect(page.getByTestId("project-file-tree")).toBeVisible({ timeout: 15_000 });
      await page.getByTestId("folder-inputs/x").click();
      const row = page.getByTestId(`file-row-${a1.id}`);
      await expect(row).toBeVisible({ timeout: 10_000 });
      await row.hover();
      await page.getByTestId(`file-rename-${a1.id}`).click();
      const input = page.getByTestId(`file-rename-${a1.id}-input`);
      await expect(input).toHaveValue("x/a.csv");
      await input.fill("y/b.csv");
      await input.press("Enter");
      await expect(page.getByTestId("folder-inputs/y")).toBeVisible({ timeout: 10_000 });
      await expect(page.getByTestId("folder-inputs/x")).toHaveCount(0);
      await expect(page.getByTestId(`file-row-${a1.id}`)).toContainText("b.csv");

      let files = await listFiles(request, projectId);
      const renamed = files.find((f) => f.id === a1.id);
      expect(renamed.name).toBe("y/b.csv");
      expect(renamed.s3_key).toBe(keyBefore); // the object did not move
      expect(await download(request, projectId, a1.id)).toBe(V2);

      const vres = await request.get(`${BASE_URL}/api/projects/${projectId}/files/${a1.id}/versions`);
      expect(vres.ok()).toBeTruthy();
      const versions = (await vres.json()).versions as Array<{ version: string; current: boolean }>;
      expect(versions.map((v) => [v.version, v.current])).toEqual([["2", true], ["1", false]]);
      const diff = await request.get(`${BASE_URL}/api/projects/${projectId}/files/${a1.id}/versions/1/diff`);
      expect(diff.ok(), `diff failed: ${await diff.text()}`).toBeTruthy();
      const dj = await diff.json();
      expect(dj.tabular).toBe(true);
      expect(dj.changedCells).toEqual([{ row: 0, col: "value", from: "10", to: "11" }]);

      // 3. an edit after the rename versions under the new name's key
      const edit = await request.post(`${BASE_URL}/api/projects/${projectId}/files/${a1.id}/edit`, {
        data: { edits: [{ row: 1, col: 1, from: "20", value: "21" }] },
      });
      expect(edit.ok(), `edit failed: ${await edit.text()}`).toBeTruthy();
      const ej = await edit.json();
      expect(ej.file.version_no).toBe(3);
      expect(ej.file.s3_key).toContain(`projects/${projectId}/inputs/y/b.csv.v3`);
      expect(await download(request, projectId, a1.id)).toBe("id,value\n1,11\n2,21\n");
      // restore v2 → v4 with the v2 bytes (restore works by id after a rename)
      const restore = await request.post(`${BASE_URL}/api/projects/${projectId}/files/${a1.id}/versions/2/restore`);
      expect(restore.ok(), `restore failed: ${await restore.text()}`).toBeTruthy();
      expect(await download(request, projectId, a1.id)).toBe(V2);

      // 4. a NEW x/a.csv is a separate file at a fresh key; the renamed file is untouched
      const fresh = await upload(request, projectId, "x/a.csv", OTHER);
      expect(fresh.id).not.toBe(a1.id);
      files = await listFiles(request, projectId);
      const freshRow = files.find((f) => f.id === fresh.id);
      expect(files.filter((f) => f.s3_key === freshRow.s3_key)).toHaveLength(1);
      expect(await download(request, projectId, fresh.id)).toBe(OTHER);
      expect(await download(request, projectId, a1.id)).toBe(V2);
      // the original v1 object (the renamed file's archived version) is also intact
      const v1diff = await request.get(`${BASE_URL}/api/projects/${projectId}/files/${a1.id}/versions/1/diff`);
      expect((await v1diff.json()).changedCells).toEqual([{ row: 0, col: "value", from: "10", to: "11" }]);

      // 5. UI folder rename y → z
      await page.getByTestId("project-files-refresh-btn").click();
      const yFolder = page.getByTestId("folder-inputs/y");
      await expect(yFolder).toBeVisible({ timeout: 10_000 });
      await yFolder.hover();
      await page.getByTestId("folder-rename-inputs/y").click();
      const fin = page.getByTestId("folder-rename-inputs/y-input");
      await expect(fin).toHaveValue("y");
      await fin.fill("z");
      await fin.press("Enter");
      await expect(page.getByTestId("folder-inputs/z")).toBeVisible({ timeout: 10_000 });
      await expect(page.getByTestId("folder-inputs/y")).toHaveCount(0);
      await expect(page.getByTestId(`file-row-${a1.id}`)).toContainText("b.csv");
      files = await listFiles(request, projectId);
      expect(files.find((f) => f.id === a1.id).name).toBe("z/b.csv");
      expect(await download(request, projectId, a1.id)).toBe(V2);

      // 6a. collision via UI: rename the new x/a.csv onto z/b.csv → 409 shown, nothing changes
      const freshRowUi = page.getByTestId(`file-row-${fresh.id}`);
      if (!(await freshRowUi.isVisible().catch(() => false))) await page.getByTestId("folder-inputs/x").click();
      await freshRowUi.hover();
      await page.getByTestId(`file-rename-${fresh.id}`).click();
      const cin = page.getByTestId(`file-rename-${fresh.id}-input`);
      await cin.fill("z/b.csv");
      await cin.press("Enter");
      await expect(page.getByTestId(`file-rename-${fresh.id}-error`)).toBeVisible({ timeout: 10_000 });
      await cin.press("Escape");
      // 6b. same via API: 409 with the clashing name
      const clash = await request.patch(`${BASE_URL}/api/projects/${projectId}/files/${fresh.id}`, { data: { name: "z/b.csv" } });
      expect(clash.status()).toBe(409);
      expect((await clash.json()).conflicts?.[0]?.existing).toBe("z/b.csv");
      // invalid name → 400
      const bad = await request.patch(`${BASE_URL}/api/projects/${projectId}/files/${fresh.id}`, { data: { name: "../escape.csv" } });
      expect(bad.status()).toBe(400);
      // 6c. folder move x → z would put x/a.csv at z/a.csv — free — but add z/a.csv first so it clashes
      await upload(request, projectId, "z/a.csv", "id,value\n5,55\n");
      const fclash = await request.post(`${BASE_URL}/api/projects/${projectId}/files/rename-folder`, { data: { from: "x", to: "z" } });
      expect(fclash.status()).toBe(409);
      files = await listFiles(request, projectId);
      expect(files.find((f) => f.id === fresh.id).name).toBe("x/a.csv"); // all-or-nothing
      expect(files.find((f) => f.id === a1.id).name).toBe("z/b.csv");

      // activity ledger records the renames
      const act = await request.get(`${BASE_URL}/api/projects/${projectId}/activity`);
      const events = ((await act.json()).activity ?? []) as Array<{ event_type: string; payload: any }>;
      const fr = events.find((e) => e.event_type === "file_renamed");
      expect(fr?.payload).toEqual({ fileId: a1.id, from: "x/a.csv", to: "y/b.csv" });
      expect(events.some((e) => e.event_type === "folder_renamed" && e.payload?.from === "y" && e.payload?.to === "z")).toBe(true);
    } finally {
      await request.delete(`${BASE_URL}/api/projects/${projectId}`).catch(() => {});
    }
  });
});
