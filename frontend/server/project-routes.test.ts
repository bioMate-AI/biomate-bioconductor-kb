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

  it("project-scoped URL import — authed, SSRF-validated, owner/editor, size-capped, records source='url'", () => {
    // Paste-a-URL ingest (spec 04 §4.6): fetches into the project's S3 prefix and
    // inserts a project_files row so it shows in the hub tree (unlike the
    // Galaxy-session /api/datasets/import-url).
    expect(SRC.match(/app\.post\("\/api\/projects\/:id\/files\/import-url",\s*authenticateToken/)?.length).toBe(1);
    expect(SRC.includes("validateRemoteFileUrl")).toBe(true);            // SSRF-safe URL check
    expect(/import-url[\s\S]{0,1200}_isOwnerOrEditor/.test(SRC)).toBe(true); // owner/editor gate
    expect(SRC.includes("512 * 1024 * 1024")).toBe(true);               // 512 MiB cap
    expect(/VALUES\s*\([^)]*'url'[^)]*\)/.test(SRC)).toBe(true);         // inserts source='url'
  });

  it("content-hash dedup (§4.5.1) — column added idempotently, computed + checked at ingest", () => {
    expect(SRC.includes("ADD COLUMN IF NOT EXISTS content_hash")).toBe(true);     // idempotent migration
    expect(SRC.includes('createHash("sha256")')).toBe(true);                       // hash at ingest
    expect((SRC.match(/_findProjectFileByHash\(/g) ?? []).length).toBeGreaterThanOrEqual(2); // upload + url ingest
    expect(SRC.includes("deduplicated: true")).toBe(true);                          // dup → link, don't re-insert
    expect(/INSERT INTO project_files[\s\S]{0,160}content_hash/.test(SRC)).toBe(true); // stored on insert
    expect(SRC.includes("input_context, content_hash, created_at")).toBe(true);     // returned by GET /files
  });

  it("every endpoint goes through authenticateToken", () => {
    // The regex only matches handlers whose path is immediately followed by
    // authenticateToken, so this count IS the authed-endpoint count. It must
    // equal the total number of project endpoints — i.e. no endpoint skips auth.
    const authed = SRC.match(/app\.(get|post|patch|delete)\("\/api\/projects[^"]*",\s*authenticateToken/g) ?? [];
    const total = SRC.match(/app\.(get|post|patch|delete)\("\/api\/projects/g) ?? [];
    expect(authed.length).toBe(total.length);
    expect(authed.length).toBe(27); // grows as endpoints are added (…, files/import-url)
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

describe("project-routes — registered into main router", () => {
  const ROUTES = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");
  it("the main router imports + calls registerProjectRoutes", () => {
    expect(/registerProjectRoutes\s*\}\s*=\s*await\s+import\("\.\/project-routes"\)/.test(ROUTES)).toBe(true);
    expect(/registerProjectRoutes\(app\)/.test(ROUTES)).toBe(true);
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
