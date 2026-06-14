/**
 * Tests for the chat-attached dataset cap.
 *
 * Policy (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md
 * §2 + clarification 2026-06-13): cap chat_sessions.datasets at
 * MAX_DATASET_REFS = 32 entries, drop OLDEST on overflow. Per-file
 * 5 GB size limit (enforced elsewhere at upload time) is orthogonal.
 */
import { describe, expect, it } from "vitest";
import { capDatasetReferences, MAX_DATASET_REFS } from "./dataset-cap";

describe("capDatasetReferences", () => {
  it("MAX_DATASET_REFS is 32 (matches prompt-block visible cap)", () => {
    expect(MAX_DATASET_REFS).toBe(32);
  });

  it("returns [] for null/undefined/non-array input", () => {
    expect(capDatasetReferences(null)).toEqual([]);
    expect(capDatasetReferences(undefined)).toEqual([]);
    expect(capDatasetReferences("not an array" as any)).toEqual([]);
    expect(capDatasetReferences({ id: 1 } as any)).toEqual([]);
  });

  it("returns input as-is when under the cap", () => {
    const input = [{ id: 1 }, { id: 2 }, { id: 3 }];
    expect(capDatasetReferences(input)).toEqual(input);
    expect(capDatasetReferences(input)).toBe(input); // same reference
  });

  it("returns the LAST 32 entries when input has 33", () => {
    const input = Array.from({ length: 33 }, (_, i) => ({ id: i }));
    const out = capDatasetReferences(input);
    expect(out.length).toBe(32);
    expect(out[0]).toEqual({ id: 1 });   // entry 0 dropped (oldest)
    expect(out[31]).toEqual({ id: 32 }); // newest kept
  });

  it("drops the oldest when given far more than the cap", () => {
    const input = Array.from({ length: 200 }, (_, i) => ({ id: i }));
    const out = capDatasetReferences(input);
    expect(out.length).toBe(32);
    expect(out[0]).toEqual({ id: 168 }); // 200 - 32
    expect(out[31]).toEqual({ id: 199 }); // newest
  });

  it("pure function — does not mutate input array", () => {
    const input = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    const snapshot = [...input];
    capDatasetReferences(input);
    expect(input).toEqual(snapshot);
  });
});

describe("dataset-cap is wired into routes.ts at every write site", () => {
  const fs = require("fs") as typeof import("fs");
  const path = require("path") as typeof import("path");
  const SRC = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");

  it("imports capDatasetReferences", () => {
    expect(/import\s*\{[\s\S]{0,200}capDatasetReferences[\s\S]{0,200}\}\s*from\s*['"]\.\/dataset-cap['"]/.test(SRC)).toBe(true);
  });

  it("applies the cap on every req.session.uploadedDatasets push site", () => {
    // Each of the three push sites must follow up with a cap call.
    // We look for the literal cap re-assignment pattern.
    const pushSites = (SRC.match(/uploadedDatasets\.push\(/g) ?? []).length;
    const capSites = (SRC.match(/uploadedDatasets\s*=\s*capDatasetReferences\(/g) ?? []).length;
    expect(capSites).toBeGreaterThanOrEqual(pushSites);
  });

  it("applies the cap on POST + PUT /api/sessions", () => {
    expect(/capDatasetReferences\(datasets\)/.test(SRC)).toBe(true);
  });

  it("applies the cap on chat_sessions rehydration into _historyDatasets", () => {
    expect(/capDatasetReferences\(_r\.datasets\)/.test(SRC)).toBe(true);
  });
});
