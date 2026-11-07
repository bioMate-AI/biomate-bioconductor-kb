/**
 * Source-level contract for the dataset "Open in" endpoint (design spec 04 §4.3.1).
 * routes.ts is too large to import, so assert the stage-and-launch shape on the
 * source — like project-routes.test.ts. The endpoint stages a project file into
 * the user's Galaxy history (uploadFromUrl) and launches an interactive tool
 * (launchInteractiveTool) against the staged HDA.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SRC = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");

describe("open-in (project file → interactive tool) — contract", () => {
  it("registers an authed POST endpoint", () => {
    expect(
      /app\.post\("\/api\/projects\/:id\/files\/:fileId\/open-in",\s*authenticateToken/.test(SRC),
    ).toBe(true);
  });
  it("gates on project membership and resolves the file from project_files", () => {
    expect(/open-in[\s\S]{0,400}_isOwnerOrMember/.test(SRC)).toBe(true);
    expect(/open-in[\s\S]{0,700}SELECT name, s3_key FROM project_files/.test(SRC)).toBe(true);
  });
  it("picks the tool by file type (R → RStudio, else Jupyter)", () => {
    expect(SRC.includes("interactive_tool_rstudio")).toBe(true);
    expect(SRC.includes("interactive_tool_jupyter_notebook")).toBe(true);
  });
  it("stages the file into a history then launches the IT against the HDA", () => {
    // presign → uploadFromUrl (stage) → launchInteractiveTool (launch), in order.
    expect(
      /open-in[\s\S]{0,1600}generatePresignedDownloadUrl[\s\S]{0,600}uploadFromUrl[\s\S]{0,600}launchInteractiveTool/.test(SRC),
    ).toBe(true);
    expect(/launchInteractiveTool\([^)]*\{\s*\n?\s*input:\s*\{\s*src:\s*"hda"/.test(SRC)).toBe(true);
  });
});
