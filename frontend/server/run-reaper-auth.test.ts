import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";

// The stale-run reaper self-calls /api/workflows/runs/:id/status, which is behind
// authenticateToken. With no credentials every call was a 401 and the reaper still logged
// "reconciled", so finished runs nobody had open stayed 'running' (2026-11-06).
describe("run-reaper calls the status route authenticated and checks the result", () => {
  const src = readFileSync(join(__dirname, "routes.ts"), "utf8");
  const body = src.slice(src.indexOf("async function reconcileStaleRuns"), src.indexOf("setInterval(() => { void reconcileStaleRuns(); }"));

  it("sends a bearer token for the run's owner", () => {
    expect(body).toContain("authService.getUserById(ownerId)");
    expect(body).toMatch(/Authorization: `Bearer \$\{authService\.generateToken\(owner/);
  });

  it("counts a call as done only when the response is ok", () => {
    expect(body).toContain("if (resp.ok) ok += 1;");
    // The old log claimed every self-call reconciled, whatever the response was.
    expect(body).not.toContain("reconciled ${batch.length}/${stale.length}");
  });
});

describe("run-reaper sweeps every stuck run and closes never-launched ones", () => {
  const src = readFileSync(join(__dirname, "routes.ts"), "utf8");
  const body = src.slice(src.indexOf("async function reconcileStaleRuns"), src.indexOf("setInterval(() => { void reconcileStaleRuns(); }"));
  it("queries non-terminal runs directly, not the newest-N window", () => {
    expect(body).toContain("storage.getNonTerminalExecutionRuns(");
    expect(body).not.toContain("storage.getExecutionRuns(");
  });
  it("fails configuring/queued runs with no Galaxy id after the window", () => {
    expect(body).toMatch(/NEVER_LAUNCHED_MS = 6 \* 60 \* 60 \* 1000/);
    expect(body).toContain("if (ex.nextflowRunId || ex.galaxyInvocationId) return false;");
  });
});

describe("status route closes runs Galaxy has lost", () => {
  const src = readFileSync(join(__dirname, "routes.ts"), "utf8");
  it("treats a Galaxy 404 'Run not found' a day after start as failed", () => {
    const i = src.indexOf("const lostState =");
    expect(i).toBeGreaterThan(0);
    const block = src.slice(i, i + 1400);
    expect(block).toContain("isNextflowRunNotFound(statusError)");
    expect(block).toContain("24 * 60 * 60 * 1000");
    expect(block).toContain("status: 'failed'");
  });
});

describe("run-reaper closes lost runs whose owner account is gone", () => {
  const src = readFileSync(join(__dirname, "routes.ts"), "utf8");
  const body = src.slice(src.indexOf("async function reconcileStaleRuns"), src.indexOf("setInterval(() => { void reconcileStaleRuns(); }"));
  it("asks Galaxy directly and applies the not-found rule", () => {
    expect(body).toContain("await galaxyAPIProxy.getNextflowStatus(nfId)");
    expect(body).toContain("if (isNextflowRunNotFound(e))");
  });
});
