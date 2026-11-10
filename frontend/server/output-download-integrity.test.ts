/**
 * Regression guards for output links discovered outside the registered
 * publishDir (the Batch work/ dir — publishDir is disabled on the head JVM).
 *
 * Before 2026-11-10 the listing marked these "download_unavailable" because the
 * download endpoint could not serve them. The endpoint now recovers them from
 * the run's OWN work dir (scoped + owner/member-authorized), so advertising the
 * download link is correct — provided that recovery branch exists and stays
 * scoped. These guards keep the listing and the endpoint in lockstep.
 */
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const routes = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf8");

describe("recovered output download integrity", () => {
  it("does NOT mark work-directory recovery artifacts unavailable (the endpoint serves them)", () => {
    const start = routes.indexOf("// workDir fallback:");
    const end = routes.indexOf("if (!outdir || !String(outdir).startsWith('s3://'))", start);
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const section = routes.slice(start, end);

    // The old "advertise nothing / 404" behavior must be gone.
    expect(section).not.toContain("download_unavailable = true");
    expect(section).not.toContain("download_unavailable_reason");
  });

  it("the download endpoint has a scoped work-dir recovery branch for these artifacts", () => {
    // The advertised /api/runs/:id/output/:name link must be backed by a real
    // recovery path, or it would 404. That path must be scoped to the run's own
    // stored work dir (no cross-run / arbitrary-key access) and reject ambiguity.
    const dl = routes.indexOf('app.get("/api/runs/:runId/output/:filename"');
    expect(dl).toBeGreaterThan(-1);
    const end = routes.indexOf("// Serve a single step output file", dl);
    const section = routes.slice(dl, end > dl ? end : dl + 12000);

    expect(section).toContain("// 3c. Work-directory recovery");
    // Scoped to the run's own stored work dir — not an arbitrary bucket/key.
    expect(section).toContain("execution?.nextflowWorkDir");
    // Exact-basename match + ambiguity rejection (no arbitrary file served).
    expect(section).toContain("is ambiguous in the work directory");
    // Recovery must NOT serve Nextflow internals (.command.*/.exitcode) — they
    // leak backend internals (ECR refs, S3 paths, injected env). Restrict to the
    // data-output allowlist, gated on the requested filename.
    expect(section).toContain("_dlNfInternals");
    expect(section).toContain("_dlIsDataOutput");
  });

  it("still injects download_url only for available files", () => {
    const loopStart = routes.indexOf("// Inject download_url for every file");
    const loopEnd = routes.indexOf("res.json({", loopStart);
    const loop = routes.slice(loopStart, loopEnd);
    // The guard that skips explicitly-unavailable files remains (defensive — any
    // other code path may still set the flag), but recovered work-dir files no
    // longer set it, so they receive a working download_url.
    expect(loop).toContain("if (f.download_unavailable) continue;");
  });
});
