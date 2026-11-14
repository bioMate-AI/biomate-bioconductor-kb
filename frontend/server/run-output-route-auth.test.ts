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
  "/api/workflows/runs/:id/logs",
  "/api/runs/:runId/output/:filename",
  // Legacy output/invocation surfaces — previously unauthenticated (IDOR).
  "/api/outputs/:id",
  "/api/outputs/:id/download",
  "/api/outputs/:id/preview",
  "/api/outputs/:id/parse",
  "/api/invocations/:id/download-all",
  "/api/invocations/:id/report",
  "/api/runs/:anyId/reproducibility-pack",
  "/api/runs/:anyId/reproducibility-record",
];

describe("run output/findings route authentication wiring", () => {
  it.each(protectedRoutes)("requires authenticateToken for %s", (route) => {
    const start = routes.indexOf(`app.get("${route}"`);
    expect(start).toBeGreaterThan(-1);
    const registration = routes.slice(start, routes.indexOf("=>", start));
    expect(registration).toContain("authenticateToken");
  });

  it("POST /api/datasets/:id/materialize requires authenticateToken + userProxy", () => {
    const start = routes.indexOf('app.post("/api/datasets/:id/materialize"');
    expect(start).toBeGreaterThan(-1);
    const registration = routes.slice(start, routes.indexOf("=>", start));
    expect(registration).toContain("authenticateToken");
    const body = routes.slice(start, start + 800);
    expect(body).toContain("userProxy(req)");
    expect(body).not.toMatch(/galaxyAPIProxy\.materializeDeferredDataset/);
  });

  it("Nextflow execute path fail-closes deferred materialize before Batch staging", () => {
    expect(routes).toContain('from "./deferred-materialize"');
    expect(routes).toContain("ensureDeferredDatasetsMaterialized");
    expect(routes).toContain("deferred_materialize_failed");
    const mat = routes.indexOf("ensureDeferredDatasetsMaterialized");
    const stage = routes.indexOf("stageLocalFilesForBatch(", mat);
    expect(mat).toBeGreaterThan(-1);
    expect(stage).toBeGreaterThan(mat);
  });

  it("does not proxy unregistered raw chain IDs without an owned run", () => {
    const start = routes.indexOf('app.get("/api/workflows/runs/:id/output_files"');
    const end = routes.indexOf('// Chain ExecutionRun', start);
    const section = routes.slice(start, end);
    expect(section).toContain('return res.status(404).json({ error: "Run not found" });');
    expect(section).not.toContain("chain_unregistered");
  });

  it('resolves ownership before fetching diagnostics and sends Nextflow to its real status route', () => {
    const start = routes.indexOf('app.get("/api/workflows/runs/:id/logs"');
    const end = routes.indexOf('app.post("/api/workflows/convert/galaxy-to-nextflow"', start);
    const section = routes.slice(start, end);
    const registration = section.slice(0, section.indexOf('=>'));
    const ownershipBeforeFetch = section.indexOf('resolveAuthorizedRun') >= 0
      && section.indexOf('resolveAuthorizedRun') < section.indexOf('await fetch(');
    expect(registration.includes('requireLegacyRunRead') || ownershipBeforeFetch).toBe(true);
    expect(section).toContain('/api/nextflow/status/${encodeURIComponent(id)}');
    expect(section).toContain('Array.isArray(data.log_tail)');
    expect(section).toContain('signal: AbortSignal.timeout(15000)');
    expect(section).toContain('!run.execution.galaxyWorkflowId');
  });
});
