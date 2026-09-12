/**
 * Regression guards for output links discovered outside the registered
 * publishDir.  A recovery listing must never advertise the registry-backed
 * download endpoint, because that endpoint correctly returns 404 until the
 * file has been published.
 */
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const routes = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf8");

describe("recovered output download integrity", () => {
  it("marks work-directory recovery artifacts unavailable rather than fabricating a download link", () => {
    const start = routes.indexOf("// workDir fallback:");
    const end = routes.indexOf("if (!outdir || !String(outdir).startsWith('s3://'))", start);
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const section = routes.slice(start, end);

    expect(section).toContain("download_unavailable = true");
    expect(section).toContain("download_unavailable_reason");
    // Do not revive the old broken `/api/runs/:id/output/:filename` link here.
    expect(section).not.toContain("download_endpoint: `/api/runs/${runId}/output/");
  });

  it("does not synthesize an endpoint for an explicitly unavailable artifact", () => {
    const loopStart = routes.indexOf("// Inject download_url for every file");
    const loopEnd = routes.indexOf("res.json({", loopStart);
    const loop = routes.slice(loopStart, loopEnd);
    expect(loop).toContain("if (f.download_unavailable) continue;");
  });
});

