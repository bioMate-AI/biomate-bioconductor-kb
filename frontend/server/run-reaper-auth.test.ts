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
    expect(body).not.toContain(".catch(() => undefined);");
  });
});
