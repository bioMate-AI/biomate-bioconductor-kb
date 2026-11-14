/**
 * Project CRUD source-level contract tests.
 *
 * Locks in the policy + ownership semantics from
 * docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md:
 *   - every endpoint scopes to req.user.id
 *   - 404 (not 403) on cross-user access — never leak existence
 *   - ensureLtmUser is called before any project op (FK precondition)
 *   - archive is soft (status='archived'); delete is hard
 *   - status updates are whitelisted to active/archived/completed
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SRC = fs.readFileSync(path.join(__dirname, "project-routes.ts"), "utf-8");

describe("project-routes — contract", () => {
  it("registers all core endpoints", () => {
    expect(SRC.match(/app\.get\("\/api\/projects"/)?.length).toBe(1);
    expect(SRC.match(/app\.post\("\/api\/projects"/)?.length).toBe(1);
    expect(SRC.match(/app\.get\("\/api\/projects\/:id"/)?.length).toBe(1);
    expect(SRC.match(/app\.patch\("\/api\/projects\/:id"/)?.length).toBe(1);
    expect(SRC.match(/app\.post\("\/api\/projects\/:id\/archive"/)?.length).toBe(1);
    expect(SRC.match(/app\.delete\("\/api\/projects\/:id"/)?.length).toBe(1);
  });

  it("registers project sessions list endpoint", () => {
    expect(SRC.match(/app\.get\("\/api\/projects\/:id\/sessions"/)?.length).toBe(1);
  });

  it("invite of a NEW (unregistered) email auto-emails the share link instead of 404", () => {
    // One invite box serves both existing members and new people: an existing
    // user is added directly; an unregistered email gets the project share link
    // emailed to it (no separate "generate link" step).
    expect(SRC.includes("sendProjectInviteEmail")).toBe(true);
    // the no-user branch creates/reuses a share token and returns pending, not 404.
    // Window widened to 2800: the branch now mints a PER-INVITE token (longer than
    // the old "reuse the single row" path) — see the per-invite-token test below.
    expect(/if \(!invitee\.rows\.length\)\s*\{[\s\S]{0,2800}pending:\s*true/.test(SRC)).toBe(true);
    expect(SRC.includes("FROM project_share_tokens WHERE project_id")).toBe(true);
    // the old hard 404 for a new email must be gone
    expect(SRC.includes('"No user found with that email"')).toBe(false);
  });

  it("new-email invite mints a PER-INVITE token (invited_email), never mutating the generic link", () => {
    // PROPER FIX for the committee privilege-escalation finding: each new-email
    // invite carries its OWN token keyed on invited_email + its own role. The
    // invite branch must NOT reuse/mutate the owner's generic share link.
    const inviteBranch =
      SRC.split("if (!invitee.rows.length)")[1]?.split("const inviteeId")[0] ?? "";
    // schema: nullable invited_email column distinguishes generic vs per-invite
    expect(SRC.includes("invited_email TEXT")).toBe(true);
    expect(SRC.includes("ADD COLUMN IF NOT EXISTS invited_email")).toBe(true);
    // looks up a PRIOR pending invite for THIS email (not the generic LIMIT 1 row)
    expect(inviteBranch.includes("WHERE project_id = $1 AND invited_email = $2")).toBe(true);
    // mints a fresh per-email token row (invited_email is set, not NULL)
    expect(/INSERT INTO project_share_tokens \(project_id, token, role, created_by, invited_email\)/.test(inviteBranch)).toBe(true);
    // re-invite to same email updates THAT row's role in place (no duplicate, no generic mutate)
    expect(/UPDATE project_share_tokens SET role = \$1, created_by = \$2 WHERE project_id = \$3 AND invited_email = \$4/.test(inviteBranch)).toBe(true);
    // must NOT fall back to the old generic "SELECT token ... WHERE project_id = $1 LIMIT 1" reuse
    expect(/SELECT token FROM project_share_tokens WHERE project_id = \$1 LIMIT 1/.test(inviteBranch)).toBe(false);
  });

  it("/share-link GET/POST/DELETE are scoped to the generic link (invited_email IS NULL)", () => {
    // Setting or revoking the owner's single share link must never touch a
    // pending per-invite token — that collision is what caused the escalation.
    const shareBlock =
      SRC.split('app.get("/api/projects/:id/share-link"')[1]
        ?.split('app.post("/api/projects/:id/plans"')[0] ?? "";
    // GET returns the generic link only
    expect(/SELECT token, role, created_at, expires_at FROM project_share_tokens WHERE project_id = \$1 AND invited_email IS NULL/.test(shareBlock)).toBe(true);
    // POST selects + updates ONLY the generic row
    expect(/SELECT token, role FROM project_share_tokens WHERE project_id = \$1 AND invited_email IS NULL/.test(shareBlock)).toBe(true);
    expect(/UPDATE project_share_tokens SET role = \$1 WHERE project_id = \$2 AND invited_email IS NULL/.test(shareBlock)).toBe(true);
    // DELETE revokes ONLY the generic link (pending invites survive)
    expect(/DELETE FROM project_share_tokens WHERE project_id = \$1 AND invited_email IS NULL/.test(shareBlock)).toBe(true);
    // the old project-wide (unscoped) DELETE that nuked every token must be gone
    expect(/DELETE FROM project_share_tokens WHERE project_id = \$1`/.test(shareBlock)).toBe(false);
  });

  it("escalation scenario: invite A viewer then B editor — A's token stays viewer", () => {
    // Walkthrough of the committee finding, enforced structurally (this is a
    // source-contract suite; no live DB):
    //   1. Invite A (viewer): INSERT a row {token: tA, role: 'viewer',
    //      invited_email: 'a@x'} — a per-email row, NOT the generic link.
    //   2. Invite B (editor): the branch looks up invited_email = 'b@x' (finds
    //      none), so it INSERTs a DISTINCT row {token: tB, role: 'editor',
    //      invited_email: 'b@x'}. It does NOT UPDATE any WHERE project_id-only
    //      row, so tA is never touched → A still joins as viewer.
    //   3. Accept reads pst.role for the SPECIFIC clicked token, so tA → viewer
    //      and tB → editor independently.
    // The guarantees that make this hold:
    const inviteBranch =
      SRC.split("if (!invitee.rows.length)")[1]?.split("const inviteeId")[0] ?? "";
    // (a) per-invite writes are always keyed by invited_email — no project-wide mutate
    expect(/UPDATE project_share_tokens[\s\S]{0,120}WHERE project_id = \$3 AND invited_email = \$4/.test(inviteBranch)).toBe(true);
    expect(/UPDATE project_share_tokens SET role = \$1 WHERE project_id = \$2`/.test(inviteBranch)).toBe(false);
    // (b) accept still reads the clicked token's own role (per-token, email-agnostic)
    const acceptBlock = SRC.split('app.post("/api/join/:token/accept"').pop() ?? "";
    expect(acceptBlock.includes("pst.role")).toBe(true);
    expect(/const \{ project_id, role, expires_at, owner_id \} = row\.rows\[0\]/.test(acceptBlock)).toBe(true);
    expect(/VALUES \(\$1, \$2, \$3, \$4\)/.test(acceptBlock)).toBe(true); // inserts member at that token's role
  });

  it("project-scoped URL import — authed, SSRF-validated, owner/editor, size-capped, records source='url'", () => {
    // Paste-a-URL ingest (spec 04 §4.6): fetches into the project's S3 prefix and
    // inserts a project_files row so it shows in the hub tree (unlike the
    // Galaxy-session /api/datasets/import-url).
    expect(SRC.match(/app\.post\("\/api\/projects\/:id\/files\/import-url",\s*authenticateToken/)?.length).toBe(1);
    expect(SRC.includes("validateRemoteFileUrl")).toBe(true);            // SSRF-safe URL check
    expect(/import-url[\s\S]{0,1200}_isOwnerOrEditor/.test(SRC)).toBe(true); // owner/editor gate
    expect(SRC.includes("512 * 1024 * 1024")).toBe(true);               // 512 MiB cap
    // Same storage path as an upload: collision-safe key from the original name, and
    // same-name/new-bytes becomes a version (never an overwrite), source='url'.
    expect(/files\/import-url[\s\S]{0,3000}projectInputPath\(rawName\)/.test(SRC)).toBe(true);
    expect(/files\/import-url[\s\S]{0,3500}_storeProjectInput\(\{[^}]*source: "url"/.test(SRC)).toBe(true);
  });

  it("content-hash dedup (§4.5.1) — column added idempotently, computed + checked at ingest", () => {
    expect(SRC.includes("ADD COLUMN IF NOT EXISTS content_hash")).toBe(true);     // idempotent migration
    expect(SRC.includes('createHash("sha256")')).toBe(true);                       // hash at ingest
    expect(/INSERT INTO project_files[\s\S]{0,160}content_hash/.test(SRC)).toBe(true); // stored on insert
    // Dedup BEHAVIOUR (same bytes → one entry, also under concurrent uploads) is tested over HTTP in
    // project-files-integrity.test.ts ("two concurrent uploads of the same bytes").
  });

  it("app-level content versioning (§4.4) — table, version-on-reupload, list + restore endpoints", () => {
    // No S3 bucket-versioning: each version is its own object + a project_file_versions row.
    expect(SRC.includes("CREATE TABLE IF NOT EXISTS project_file_versions")).toBe(true);
    expect(SRC.includes("ADD COLUMN IF NOT EXISTS version_no")).toBe(true);
    // re-upload same name + different content → new version: behaviour in project-files-integrity.test.ts.
    // list + restore endpoints, authed
    expect(/app\.get\("\/api\/projects\/:id\/files\/:fileId\/versions",\s*authenticateToken/.test(SRC)).toBe(true);
    expect(/app\.post\("\/api\/projects\/:id\/files\/:fileId\/versions\/:versionNo\/restore",\s*authenticateToken/.test(SRC)).toBe(true);
    // append-only history for reupload / edit / restore (and its version precondition): behaviour
    // in project-files-integrity.test.ts.
  });

  it("version Compare/diff (§4.4) — authed endpoint reads both versions, column + cell diff", () => {
    expect(/app\.get\("\/api\/projects\/:id\/files\/:fileId\/versions\/:versionNo\/diff",\s*authenticateToken/.test(SRC)).toBe(true);
    // Row numbering by the reader's layout, read errors → 502 and the cell diff are BEHAVIOUR-tested
    // in project-rows-edit-roundtrip.test.ts and project-files-integrity.test.ts.
    expect(/columns:\s*\{\s*added,\s*removed\s*\}/.test(SRC)).toBe(true);
  });

  it("edit-in-place → new version (§4.3/§4.4) — authed, tabular-only, size-capped, applies to FULL file, versions", () => {
    expect(/app\.post\("\/api\/projects\/:id\/files\/:fileId\/edit",\s*authenticateToken/.test(SRC)).toBe(true);
    expect(/edit[\s\S]{0,700}_isOwnerOrEditor/.test(SRC)).toBe(true);                 // editor gate
    // tabular-only: behaviour-tested (.bed / .json / .jsonl → 400, nothing written) in
    // project-files-integrity.test.ts "edit — tabular files only".
    expect(SRC.includes("10 * 1024 * 1024")).toBe(true);                              // 10 MiB cap
    // The edit's safety checks are BEHAVIOUR-tested (project-files-integrity.test.ts): whole-file read
    // (2.7 MB CSV), baseVersion → 409 version_conflict, cell/rowFrom → 409 cell_conflict, strict
    // UTF-8 → 422, 413, append-only version. Source regexes here could not catch them being disabled.
  });

  it("every endpoint goes through authenticateToken", () => {
    // The regex only matches handlers whose path is immediately followed by
    // authenticateToken, so this count IS the authed-endpoint count. It must
    // equal the total number of project endpoints — i.e. no endpoint skips auth.
    const authed = SRC.match(/app\.(get|post|patch|delete)\("\/api\/projects[^"]*",\s*authenticateToken/g) ?? [];
    const total = SRC.match(/app\.(get|post|patch|delete)\("\/api\/projects/g) ?? [];
    expect(authed.length).toBe(total.length);
    expect(authed.length).toBe(40); // grows as endpoints are added (+1 files/:fileId/preview.png 2026-11-12; +1 versions/:versionNo/url 2026-11-12; +1 folders/profile 2026-11-11; +2 file rename/move 2026-11-11; …, files/import-url, files/:fileId/versions GET + restore POST + diff, edit, rows)
  });

  it("404 on cross-user access (does not leak existence)", () => {
    // Every per-id endpoint (GET :id, PATCH, archive, DELETE) checks
    // ownership before returning. Use a regex that accepts either
    // `existing.userId` (PATCH/archive/DELETE pattern) or `project.userId`
    // (GET :id pattern) — both are valid as long as the comparison + 404
    // pair is right there.
    const ownershipCheck = /(?:existing|project)\.userId\s*!==\s*uid[\s\S]{0,80}404[\s\S]{0,80}Project not found/g;
    const matches = SRC.match(ownershipCheck) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(4);
  });

  it("ensureLtmUser is called before list and create (FK precondition)", () => {
    expect(SRC.includes("memoryService.ensureLtmUser")).toBe(true);
    // It must appear in both the list (GET /api/projects) and create
    // (POST /api/projects) branches so a brand-new user can use the
    // API before they've ever chatted.
    const listBlock = SRC.split('app.get("/api/projects"')[1]?.split('app.post("/api/projects"')[0] ?? '';
    const createBlock = SRC.split('app.post("/api/projects"')[1]?.split('app.get("/api/projects/:id"')[0] ?? '';
    expect(listBlock.includes("ensureLtmUser")).toBe(true);
    expect(createBlock.includes("ensureLtmUser")).toBe(true);
  });

  it("PATCH whitelists status values to active/archived/completed", () => {
    expect(/\["active",\s*"archived",\s*"completed"\]/.test(SRC)).toBe(true);
  });

  it("POST validates name (required, max 255)", () => {
    expect(/name is required/.test(SRC)).toBe(true);
    expect(/name too long \(max 255 chars\)/.test(SRC)).toBe(true);
  });

  it("archive is soft (calls archiveProject not deleteProject)", () => {
    const archiveBlock = SRC.split('/archive"')[1]?.split('app.delete')[0] ?? '';
    expect(archiveBlock.includes("archiveProject")).toBe(true);
    expect(archiveBlock.includes("deleteProject")).toBe(false);
  });

  it("DELETE is hard (calls deleteProject)", () => {
    const deleteBlock = SRC.split('app.delete("/api/projects/:id"')[1] ?? '';
    expect(deleteBlock.includes("memoryService.projects.deleteProject")).toBe(true);
  });
});

describe("project-routes — file rename / move", () => {
  const patchBlock = SRC.split('app.patch("/api/projects/:id/files/:fileId"')[1]?.split("app.post(")[0] ?? "";
  const folderBlock = SRC.split('app.post("/api/projects/:id/files/rename-folder"')[1]?.split("app.delete(")[0] ?? "";
  const applyBlock = SRC.split("async function _applyRenamePlan")[1]?.split("\nfunction ")[0] ?? "";

  it("registers PATCH /files/:fileId and POST /files/rename-folder, both authenticated", () => {
    expect(SRC.match(/app\.patch\("\/api\/projects\/:id\/files\/:fileId", authenticateToken/g)?.length).toBe(1);
    expect(SRC.match(/app\.post\("\/api\/projects\/:id\/files\/rename-folder", authenticateToken/g)?.length).toBe(1);
  });

  it("owner/editor only, 404 otherwise (never leak existence)", () => {
    for (const b of [patchBlock, folderBlock]) {
      expect(/if \(!\(await _isOwnerOrEditor\(id, uid\)\)\) return res\.status\(404\)/.test(b)).toBe(true);
    }
  });

  it("names go through the shared pure planners (sanitize + collision), not ad-hoc checks", () => {
    expect(patchBlock.includes("planFileRename(rows, fileId, req.body?.name)")).toBe(true);
    expect(folderBlock.includes("planFolderRename(rows, req.body?.from, req.body?.to)")).toBe(true);
    // the planner's status (400/404/409) is what the client sees
    expect(patchBlock.includes("res.status(out.status)")).toBe(true);
    expect(folderBlock.includes("res.status(out.status)")).toBe(true);
  });

  it("applies the plan in one transaction, serialized per project, computed from rows read under the lock", () => {
    // The shared project lock (renames, uploads, edits, restores, deletes all take it).
    const lockBlock = SRC.split("async function _withProjectLock")[1]?.split("\n}")[0] ?? "";
    expect(lockBlock.includes('client.query("BEGIN")')).toBe(true);
    expect(lockBlock.indexOf("pg_advisory_xact_lock")).toBeLessThan(lockBlock.indexOf("await fn(client)"));
    expect(lockBlock.includes('client.query("COMMIT")')).toBe(true);
    expect(lockBlock.includes('client.query("ROLLBACK")')).toBe(true);
    expect(lockBlock.includes("client.release()")).toBe(true);
    expect(applyBlock.includes("_withProjectLock(projectId")).toBe(true);
    expect(applyBlock.indexOf("_withProjectLock(projectId")).toBeLessThan(applyBlock.indexOf("FROM project_files WHERE project_id::text = $1"));
    // uuid columns compared as text (a non-uuid param must not throw a cast error)
    expect(applyBlock.includes("f.id::text = v.id AND f.project_id::text = $3")).toBe(true);
  });

  it("only the name changes — S3 objects are not moved or deleted by a rename", () => {
    for (const b of [patchBlock, folderBlock, applyBlock]) {
      expect(/s3Service\.(putObject|deleteFile|copy)/.test(b)).toBe(false);
      expect(/SET s3_key/.test(b)).toBe(false);
    }
    expect(applyBlock.includes("SET name = v.new_name")).toBe(true);
  });

  it("records file_renamed {fileId, from, to} and folder_renamed activity", () => {
    expect(SRC.includes('| "file_renamed"')).toBe(true);
    expect(SRC.includes('| "folder_renamed"')).toBe(true);
    expect(patchBlock.includes('recordProjectActivity(id, uid, "file_renamed", { fileId: m.id, from: m.from, to: m.to })')).toBe(true);
    expect(folderBlock.includes('recordProjectActivity(id, uid, "folder_renamed"')).toBe(true);
  });

  it("every NEW object key is allocated so it can't overwrite bytes a renamed file still uses", () => {
    // Allocation checks current files, archived versions AND in-flight reservations (the fake store
    // in the behaviour tests implements these three sources, so the SQL is pinned here).
    const alloc = SRC.split("async function _allocateObjectKey")[1]?.split("\n}")[0] ?? "";
    expect(alloc.includes("FROM project_files WHERE project_id::text = $1")).toBe(true);
    expect(alloc.includes("FROM project_file_versions WHERE project_id::text = $1")).toBe(true);
    expect(alloc.includes("FROM project_object_key_reservations")).toBe(true);
    // Concurrent same-name uploads (S2) are behaviour-tested in project-files-integrity.test.ts.
  });
});

describe("project-routes — registered into main router", () => {
  const ROUTES = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");
  it("the main router imports + calls registerProjectRoutes", () => {
    expect(/registerProjectRoutes\s*\}\s*=\s*await\s+import\("\.\/project-routes"\)/.test(ROUTES)).toBe(true);
    expect(/registerProjectRoutes\(app\)/.test(ROUTES)).toBe(true);
  });
  it("launching a project-scoped run is editor-gated (viewers cannot start runs)", () => {
    expect(ROUTES.includes("_isOwnerOrEditor")).toBe(true);
    // the /api/workflows/execute path rejects a viewer with a 403 when request.projectId is set
    expect(/request\.projectId[\s\S]{0,160}_isOwnerOrEditor[\s\S]{0,160}forbidden_viewer_run/.test(ROUTES)).toBe(true);
  });
});

describe("MemoryService — new archive + delete helpers", () => {
  const MEM = fs.readFileSync(path.join(__dirname, "memory-repository.ts"), "utf-8");

  it("ProjectMemoryRepository.archiveProject sets status='archived' via update", () => {
    expect(/async\s+archiveProject\(\s*projectId\s*:\s*string\s*\)\s*:\s*Promise<Project\s*\|\s*null>/.test(MEM)).toBe(true);
    expect(/status:\s*['"]archived['"]/.test(MEM)).toBe(true);
  });

  it("ProjectMemoryRepository.deleteProject hard-deletes and returns boolean", () => {
    expect(/async\s+deleteProject\(\s*projectId\s*:\s*string\s*\)\s*:\s*Promise<boolean>/.test(MEM)).toBe(true);
    expect(/db\.delete\(ltmSchema\.projects\)/.test(MEM)).toBe(true);
  });
});
