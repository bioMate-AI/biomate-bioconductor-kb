/**
 * Workbench (pinboard) source-level contract tests.
 *
 * Same shape as notes-routes.test.ts and project-routes.test.ts —
 * locks in the policy invariants without booting Postgres. Scenarios:
 *   (a) unauthenticated → 401
 *   (b) non-member (cross-user) → 404 (never leak existence)
 *   (c) POST without required fields → 400
 *   (d) DELETE with non-numeric id → 400
 *   (e) DELETE of a non-existent pin → 404
 *   (f) cross-project deletes are impossible (scope-by-project in repo)
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SRC = fs.readFileSync(path.join(__dirname, "workbench-routes.ts"), "utf-8");
const REPO_SRC = fs.readFileSync(
  path.join(__dirname, "memory-repository.ts"),
  "utf-8",
);

describe("workbench-routes — contract", () => {
  it("registers all three endpoints", () => {
    expect(
      SRC.match(/app\.get\(\s*"\/api\/projects\/:projectId\/workbench\/pins"/)?.length,
    ).toBe(1);
    expect(
      SRC.match(/app\.post\(\s*"\/api\/projects\/:projectId\/workbench\/pins"/)?.length,
    ).toBe(1);
    expect(
      SRC.match(/app\.delete\(\s*"\/api\/projects\/:projectId\/workbench\/pins\/:pinId"/)?.length,
    ).toBe(1);
  });

  it("all endpoints go through authenticateToken", () => {
    const handlers =
      SRC.match(
        /app\.(get|post|delete)\(\s*"\/api\/projects\/:projectId\/workbench\/pins[^"]*",\s*\n?\s*authenticateToken/g,
      ) ?? [];
    expect(handlers.length).toBe(3);
  });

  it("(a) unauthenticated request short-circuits with 401", () => {
    const matches = SRC.match(/if\s*\(!uid\)\s*return\s+res\.status\(401\)/g) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(3);
  });

  it("(b) cross-user / unknown project returns 404 (not 403) on every endpoint", () => {
    // Each handler does: getProject; if !project || project.userId !== uid → 404.
    const checks =
      SRC.match(
        /if\s*\(!project\s*\|\|\s*project\.userId\s*!==\s*uid\)\s*\{\s*\n?\s*return\s+res\.status\(404\)/g,
      ) ?? [];
    expect(checks.length).toBe(3);
  });

  it("(c) POST validates required fields and 400s when missing", () => {
    expect(
      SRC.includes("runId, filePath, and fileName are required"),
    ).toBe(true);
    expect(
      SRC.match(/res\.status\(400\)\.json\(\s*\{\s*\n?\s*error:\s*"runId, filePath, and fileName are required"/)?.length,
    ).toBe(1);
  });

  it("(d) DELETE with non-numeric / non-positive id returns 400", () => {
    expect(SRC.includes('error: "Invalid pin id"')).toBe(true);
    expect(SRC.includes("Number.isFinite(pinId)")).toBe(true);
  });

  it("(e) DELETE of a non-existent pin returns 404", () => {
    expect(SRC.includes('error: "Pin not found"')).toBe(true);
    expect(
      SRC.match(/if\s*\(!ok\)\s*\{\s*\n?\s*return\s+res\.status\(404\)\.json\(\s*\{\s*error:\s*"Pin not found"/)?.length,
    ).toBe(1);
  });

  it("(f) cross-project deletes are impossible — repo scopes by projectId", () => {
    // The repo's deleteProjectKnowledgeRow takes BOTH projectId and rowId
    // and ANDs them in the WHERE clause. A caller in project X cannot
    // delete a row owned by project Y even if they guess Y's row id.
    expect(REPO_SRC.includes("deleteProjectKnowledgeRow")).toBe(true);
    const repoMethod = REPO_SRC.match(
      /async\s+deleteProjectKnowledgeRow\([\s\S]*?\)\s*:\s*Promise<boolean>\s*\{[\s\S]*?\n\s{2}\}/,
    )?.[0] ?? "";
    expect(repoMethod).toContain("eq(ltmSchema.projectKnowledge.id, rowId)");
    expect(repoMethod).toContain(
      "eq(ltmSchema.projectKnowledge.projectId, projectId)",
    );
    expect(repoMethod).toMatch(/and\(/);
  });

  it("pin payload shape is well-defined (runId, filePath, fileName, optional fileSize)", () => {
    expect(SRC.includes("interface PinPayload")).toBe(true);
    expect(SRC.includes("runId: string")).toBe(true);
    expect(SRC.includes("filePath: string")).toBe(true);
    expect(SRC.includes("fileName: string")).toBe(true);
    expect(SRC.includes("fileSize?: number")).toBe(true);
  });

  it("storage type is workbench_pin (not a new table)", () => {
    expect(
      SRC.includes('const WORKBENCH_PIN_TYPE = "workbench_pin"'),
    ).toBe(true);
    // Reuses memoryService.projects.addProjectKnowledge / getProjectKnowledge /
    // deleteProjectKnowledgeRow — no new table.
    expect(SRC.includes("addProjectKnowledge")).toBe(true);
    expect(SRC.includes("getProjectKnowledge")).toBe(true);
    expect(SRC.includes("deleteProjectKnowledgeRow")).toBe(true);
  });

  it("list endpoint sorts newest-first", () => {
    // After parsing pins, the GET handler sorts by createdAt desc.
    expect(SRC.match(/return\s+bt\s*-\s*at/)?.length ?? 0).toBeGreaterThanOrEqual(1);
  });

  it("malformed JSON in stored content is skipped, not crashed on", () => {
    // parsePin returns null on bad JSON; the GET handler filters those out.
    expect(SRC.includes("parsePin")).toBe(true);
    expect(SRC.match(/p\s*!==\s*null/)?.length ?? 0).toBeGreaterThanOrEqual(1);
  });
});
