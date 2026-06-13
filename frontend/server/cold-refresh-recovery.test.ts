/**
 * Tests for the cold-refresh dataset recovery within a project.
 *
 * Policy: docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
 * Source-level guards cover:
 *   - the SQL query is project-scoped (NOT user-scoped, NOT cross-project)
 *   - excludes the current session
 *   - 14-day window
 *   - LIMIT 20, DISTINCT by dataset id
 *   - chat-stream only runs recovery when projectId is set (project-less
 *     sessions have no scope to recover within)
 *   - recovered entries carry `recovered: true` so the prompt block
 *     labels them distinctly
 *   - the prompt block uses the right anti-confabulation wording
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SRC = path.join(__dirname);

describe("cold-refresh recovery — SQL + helper", () => {
  const MEM = fs.readFileSync(path.join(SRC, "memory-repository.ts"), "utf-8");

  it("MemoryService.recoverProjectDatasets(projectId, currentChatSessionId) is declared", () => {
    expect(/async\s+recoverProjectDatasets\s*\([\s\S]{0,300}\)\s*:\s*Promise<Array<\{[\s\S]{0,500}\}>>/.test(MEM)).toBe(true);
  });

  it("query scopes by project_id (NOT user_id) and excludes current session", () => {
    const body = MEM.split("async recoverProjectDatasets")[1]?.split("\n  /**")[0] ?? "";
    expect(body.includes("cs.project_id = $1")).toBe(true);
    expect(body.includes("cs.session_id != $2")).toBe(true);
    // Smoking-gun negative: no user_id fallback (would re-introduce
    // the inverse bug — datasets from project A leaking into project B).
    expect(/user_id\s*=/.test(body)).toBe(false);
  });

  it("14-day window + LIMIT 20 + DISTINCT id (dedup across sister sessions)", () => {
    const body = MEM.split("async recoverProjectDatasets")[1]?.split("\n  /**")[0] ?? "";
    expect(body.includes("INTERVAL '14 days'")).toBe(true);
    expect(body.includes("LIMIT 20")).toBe(true);
    expect(/DISTINCT ON \(d->>'id'\)/.test(body)).toBe(true);
  });

  it("returned entries carry recovered:true + sourceSessionId for traceability", () => {
    const body = MEM.split("async recoverProjectDatasets")[1]?.split("\n  /**")[0] ?? "";
    expect(/recovered:\s*true\s*as\s*const/.test(body)).toBe(true);
    expect(body.includes("sourceSessionId")).toBe(true);
  });

  it("degrades to [] on any DB error (chat must not break)", () => {
    const body = MEM.split("async recoverProjectDatasets")[1]?.split("\n  /**")[0] ?? "";
    expect(body.includes("} catch")).toBe(true);
    expect(body.includes("return []")).toBe(true);
  });
});

describe("cold-refresh recovery — chat-stream wiring", () => {
  const ROUTES = fs.readFileSync(path.join(SRC, "routes.ts"), "utf-8");

  it("only runs recovery when the chat is project-scoped", () => {
    // The call must be gated on _resolvedProjectId being non-null.
    expect(/if\s*\(\s*_resolvedProjectId\s*\)\s*\{[\s\S]{0,200}recoverProjectDatasets/.test(ROUTES)).toBe(true);
  });

  it("recovered datasets are deduplicated against direct attachments before merging", () => {
    expect(/seen = new Set\(direct\.map\(/.test(ROUTES)).toBe(true);
    expect(/_recoveredDatasets[\s\S]{0,200}\.filter\(\(r\)\s*=>\s*!seen\.has\(r\.id\)\)/.test(ROUTES)).toBe(true);
  });

  it("merged sessionDatasets carries the recovered flag through to galaxy-assistant", () => {
    expect(/recovered:\s*true/.test(ROUTES)).toBe(true);
    expect(/sourceSessionId:\s*r\.sourceSessionId/.test(ROUTES)).toBe(true);
  });
});

describe("cold-refresh recovery — sessionDatasetsBlock surfaces distinct labels", () => {
  const ASSIST = fs.readFileSync(path.join(SRC, "galaxy-assistant.ts"), "utf-8");

  it("splits direct vs recovered groups", () => {
    expect(/const direct = valid\.filter\(d\s*=>\s*!d\.recovered\)/.test(ASSIST)).toBe(true);
    expect(/const recovered = valid\.filter\(d\s*=>\s*d\.recovered\)/.test(ASSIST)).toBe(true);
  });

  it("recovered group is labeled 'from earlier sessions in this project'", () => {
    expect(/Datasets from earlier sessions in this project \(recovered after refresh/.test(ASSIST)).toBe(true);
  });

  it("anti-confabulation: instructs LLM never to claim user attached recovered ones this turn", () => {
    expect(/never claim the user attached them this turn/.test(ASSIST)).toBe(true);
  });

  it("recovered cap is independent from direct cap (20 vs 32)", () => {
    expect(/direct = valid\.filter[\s\S]{0,80}\.slice\(0, 32\)/.test(ASSIST)).toBe(true);
    expect(/recovered = valid\.filter[\s\S]{0,80}\.slice\(0, 20\)/.test(ASSIST)).toBe(true);
  });
});
