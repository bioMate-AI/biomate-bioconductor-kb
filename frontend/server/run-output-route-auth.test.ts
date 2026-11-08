/**
 * Route wiring regression tests. The decision policy itself is exercised over
 * 401/403/owner cases in run-access.test.ts; these assertions ensure every
 * externally reachable output/findings alias invokes authenticated routing.
 */
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const routes = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf8");

const protectedRoutes = [
  "/api/runs/:anyId/outputs",
  "/api/runs/:anyId/meta",
  "/api/workflows/runs/:id/output_files",
  "/api/workflows/runs/:id/outputs",
  "/api/workflows/runs/:id/findings",
  "/api/workflows/runs/:id/findings/report",
  "/api/runs/:runId/output/:filename",
  // Legacy output/invocation surfaces — previously unauthenticated (IDOR).
  "/api/outputs/:id",
  "/api/outputs/:id/download",
  "/api/outputs/:id/preview",
  "/api/outputs/:id/parse",
  "/api/invocations/:id/download-all",
  "/api/invocations/:id/report",
];

describe("run output/findings route authentication wiring", () => {
  it.each(protectedRoutes)("requires authenticateToken for %s", (route) => {
    const start = routes.indexOf(`app.get("${route}"`);
    expect(start).toBeGreaterThan(-1);
    const registration = routes.slice(start, routes.indexOf("=>", start));
    expect(registration).toContain("authenticateToken");
  });

  it("does not proxy unregistered raw chain IDs without an owned run", () => {
    const start = routes.indexOf('app.get("/api/workflows/runs/:id/output_files"');
    const end = routes.indexOf('// Chain ExecutionRun', start);
    const section = routes.slice(start, end);
    expect(section).toContain('return res.status(404).json({ error: "Run not found" });');
    expect(section).not.toContain("chain_unregistered");
  });
});
