/**
 * Project Notes (synthesis) source-level contract tests.
 *
 * Same pattern as project-routes.test.ts — locks in the policy
 * invariants without booting Postgres or calling Gemini. The four
 * scenarios from the task spec are covered as source-text assertions:
 *   (a) unauthenticated → 401
 *   (b) non-member (cross-user) → 404 (never leak existence)
 *   (c) GET when no synthesis exists → 404
 *   (d) POST → creates a row via memoryService.projects.addProjectKnowledge
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SRC = fs.readFileSync(path.join(__dirname, "notes-routes.ts"), "utf-8");

describe("notes-routes — contract", () => {
  it("registers both endpoints", () => {
    expect(
      SRC.match(/app\.post\(\s*"\/api\/projects\/:projectId\/notes\/refresh"/)?.length,
    ).toBe(1);
    expect(
      SRC.match(/app\.get\(\s*"\/api\/projects\/:projectId\/notes"/)?.length,
    ).toBe(1);
  });

  it("both endpoints go through authenticateToken", () => {
    const handlers =
      SRC.match(
        /app\.(get|post)\(\s*"\/api\/projects\/:projectId\/notes[^"]*",\s*\n?\s*authenticateToken/g,
      ) ?? [];
    expect(handlers.length).toBe(2);
  });

  it("(a) unauthenticated request short-circuits with 401", () => {
    // Both handlers call userId(req); if null, return 401.
    const matches = SRC.match(/if\s*\(!uid\)\s*return\s+res\.status\(401\)/g) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(2);
  });

  it("(b) cross-user access returns 404 (never leak existence)", () => {
    const ownership =
      /project\.userId\s*!==\s*uid[\s\S]{0,80}404[\s\S]{0,80}Project not found/g;
    const matches = SRC.match(ownership) ?? [];
    // One per endpoint (refresh + get).
    expect(matches.length).toBeGreaterThanOrEqual(2);
  });

  it("(c) GET returns 404 when no synthesis exists", () => {
    expect(/No synthesis yet/.test(SRC)).toBe(true);
    const getBlock = SRC.split('app.get(')[1] ?? "";
    expect(/!rows\s*\|\|\s*rows\.length\s*===\s*0[\s\S]{0,80}404/.test(getBlock)).toBe(
      true,
    );
  });

  it("(d) POST creates a row via addProjectKnowledge with type=notes_synthesis", () => {
    expect(SRC.includes("addProjectKnowledge")).toBe(true);
    expect(/knowledgeType:\s*NOTES_TYPE/.test(SRC)).toBe(true);
    expect(/const\s+NOTES_TYPE\s*=\s*"notes_synthesis"/.test(SRC)).toBe(true);
    // Returns 201 with the saved note.
    expect(/res\.status\(201\)\.json\(\{\s*note:\s*saved\s*\}\)/.test(SRC)).toBe(true);
  });

  it("uses callGeminiFlash with bounded maxTokens for cost control", () => {
    expect(SRC.includes("callGeminiFlash")).toBe(true);
    expect(/LLM_MAX_TOKENS\s*=\s*4096/.test(SRC)).toBe(true);
    expect(/maxTokens:\s*LLM_MAX_TOKENS/.test(SRC)).toBe(true);
  });

  it("LLM failure surfaces as 502, not 500", () => {
    // Distinguishes upstream failure (Gemini) from internal bug.
    expect(/LLM synthesis failed/.test(SRC)).toBe(true);
    expect(/return\s+res\.status\(502\)/.test(SRC)).toBe(true);
  });

  it("chat lookback window is 30 days per spec", () => {
    expect(/CHAT_LOOKBACK_DAYS\s*=\s*30/.test(SRC)).toBe(true);
  });

  it("latest note picked by createdAt desc (not relevanceScore which is constant)", () => {
    expect(/sort\([\s\S]*createdAt[\s\S]*\)/.test(SRC)).toBe(true);
  });
});

describe("notes-routes — registered into main router", () => {
  const ROUTES = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");
  it("the main router imports + calls registerNotesRoutes", () => {
    expect(
      /registerNotesRoutes\s*\}\s*=\s*await\s+import\("\.\/notes-routes"\)/.test(
        ROUTES,
      ),
    ).toBe(true);
    expect(/registerNotesRoutes\(app\)/.test(ROUTES)).toBe(true);
  });
});

describe("shared/schema — projectDocumentSchema accepts notes_synthesis", () => {
  const SCHEMA = fs.readFileSync(
    path.join(__dirname, "..", "shared", "schema.ts"),
    "utf-8",
  );
  it("type enum now includes notes_synthesis", () => {
    expect(
      /type:\s*z\.enum\(\[\s*"file",\s*"text",\s*"url",\s*"notes_synthesis"\s*\]\)/.test(
        SCHEMA,
      ),
    ).toBe(true);
  });
});
