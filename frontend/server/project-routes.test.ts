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

  it("every endpoint goes through authenticateToken", () => {
    const handlerLines = SRC.match(/app\.(get|post|patch|delete)\("\/api\/projects[^"]*",\s*authenticateToken/g) ?? [];
    expect(handlerLines.length).toBe(18);
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
