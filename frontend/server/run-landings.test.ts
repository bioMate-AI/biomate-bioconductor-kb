/**
 * Wave 4 — BioMate-native run landing contracts.
 * Source + pure-helper tests (no live DB).
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";
import {
  validateCreateBody,
  buildPanelWorkflow,
  isExpired,
  claimUrlForToken,
} from "./run-landings";

const SRC = fs.readFileSync(path.join(__dirname, "run-landings.ts"), "utf-8");
const ROUTES = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");
const APP = fs.readFileSync(path.join(__dirname, "../client/src/App.tsx"), "utf-8");
const PAGE = fs.readFileSync(path.join(__dirname, "../client/src/pages/RunLanding.tsx"), "utf-8");
const DEEP = fs.readFileSync(path.join(__dirname, "../client/src/pages/WorkflowDeepLink.tsx"), "utf-8");
const MIGRATION = fs.readFileSync(
  path.join(__dirname, "../migrations/0024_run_landings.sql"),
  "utf-8",
);
const VIEW_MODEL = fs.readFileSync(
  path.join(__dirname, "../client/src/components/datasets/dataset-view-model.ts"),
  "utf-8",
);

describe("run-landings — routes registered", () => {
  it("exposes create / preview / claim / revoke endpoints", () => {
    expect(SRC.includes('"/api/workflows/landings"')).toBe(true);
    expect(SRC.includes('"/api/workflows/landings/:token"')).toBe(true);
    expect(SRC.includes('"/api/workflows/landings/:token/claim"')).toBe(true);
    expect(/app\.post\([\s\S]{0,80}"\/api\/workflows\/landings"/.test(SRC)).toBe(true);
    expect(/app\.get\([\s\S]{0,80}"\/api\/workflows\/landings\/:token"/.test(SRC)).toBe(true);
    expect(/app\.post\([\s\S]{0,120}"\/api\/workflows\/landings\/:token\/claim"/.test(SRC)).toBe(true);
    expect(/app\.delete\([\s\S]{0,120}"\/api\/workflows\/landings\/:token"/.test(SRC)).toBe(true);
  });

  it("create + claim + revoke require authenticateToken", () => {
    expect(/app\.post\("\/api\/workflows\/landings",\s*authenticateToken/.test(SRC)).toBe(true);
    expect(
      /app\.post\(\s*"\/api\/workflows\/landings\/:token\/claim",\s*authenticateToken/.test(SRC),
    ).toBe(true);
    expect(
      /app\.delete\(\s*"\/api\/workflows\/landings\/:token",\s*authenticateToken/.test(SRC),
    ).toBe(true);
  });

  it("main router imports + registers run landing routes", () => {
    expect(/registerRunLandingRoutes/.test(ROUTES)).toBe(true);
    expect(/import\("\.\/run-landings"\)/.test(ROUTES)).toBe(true);
  });

  it("App mounts /run/:token distinct from /workflow/:id", () => {
    expect(APP.includes('path="/run/:token"')).toBe(true);
    expect(APP.includes("RunLanding")).toBe(true);
    expect(APP.includes('path="/workflow/:id"')).toBe(true);
    expect(DEEP.includes("/workflow/:id")).toBe(true);
    expect(PAGE.includes("/run/:token")).toBe(true);
    expect(PAGE.includes("run_landing")).toBe(true);
  });

  it("migration creates run_landings table", () => {
    expect(MIGRATION.includes("CREATE TABLE IF NOT EXISTS run_landings")).toBe(true);
    expect(MIGRATION.includes("token")).toBe(true);
    expect(MIGRATION.includes("params")).toBe(true);
    expect(MIGRATION.includes("dataset_refs")).toBe(true);
  });

  it("does not re-enable Galaxy Open-in or proxy Galaxy landings API", () => {
    expect(/OPEN_IN_AVAILABLE\s*=\s*false/.test(VIEW_MODEL)).toBe(true);
    expect(SRC.includes("OPEN_IN_AVAILABLE")).toBe(false);
    // Must not mount Galaxy's /api/workflow_landings — BioMate path is /api/workflows/landings.
    expect(SRC.includes('"/api/workflow_landings"')).toBe(false);
    expect(SRC.includes("landing_manager")).toBe(false);
  });
});

describe("run-landings — validateCreateBody", () => {
  it("rejects empty body", () => {
    const r = validateCreateBody(null);
    expect(r.ok).toBe(false);
  });

  it("rejects body with no workflow identity", () => {
    const r = validateCreateBody({ params: { a: 1 } });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.status).toBe(400);
  });

  it("accepts nextflowPath + params", () => {
    const r = validateCreateBody({
      nextflowPath: "nf-core/rnaseq",
      workflowName: "RNA-seq",
      params: { genome: "GRCh38" },
      datasetRefs: [{ param: "input", s3Uri: "s3://x/y.fastq" }],
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.nextflowPath).toBe("nf-core/rnaseq");
      expect(r.value.params).toEqual({ genome: "GRCh38" });
      expect(r.value.expiresInDays).toBe(30);
      expect(r.value.datasetRefs).toHaveLength(1);
    }
  });

  it("clamps expiresInDays to max 90", () => {
    const r = validateCreateBody({ workflowId: "w1", expiresInDays: 365 });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.expiresInDays).toBe(90);
  });
});

describe("run-landings — buildPanelWorkflow + expiry", () => {
  it("merges params into inline_parameters", () => {
    const panel = buildPanelWorkflow({
      workflow: { name: "ADMET", domain: "drug_discovery", inline_parameters: { smiles: "C" } },
      params: { smiles: "CCO", herg_threshold: "5" },
      nextflow_path: "custom/admet",
    });
    expect(panel.name).toBe("ADMET");
    expect((panel as any).inline_parameters).toEqual({
      smiles: "CCO",
      herg_threshold: "5",
    });
    expect((panel as any).nextflow_path).toBe("custom/admet");
  });

  it("isExpired respects null and past dates", () => {
    expect(isExpired(null)).toBe(false);
    expect(isExpired(new Date(Date.now() + 60_000))).toBe(false);
    expect(isExpired(new Date(Date.now() - 60_000))).toBe(true);
  });

  it("claimUrlForToken builds /run/:token path", () => {
    const prev = process.env.APP_URL;
    process.env.APP_URL = "https://dev-public.biomate.ai";
    try {
      expect(claimUrlForToken("abcToken")).toBe("https://dev-public.biomate.ai/run/abcToken");
    } finally {
      if (prev === undefined) delete process.env.APP_URL;
      else process.env.APP_URL = prev;
    }
  });
});
