import { describe, it, expect, vi, beforeEach } from "vitest";

// Stub the DB layer so createExecutionRun's fire-and-forget persistence is a
// no-op (no real Postgres). MemStorage is the primary store for active runs;
// this exercises the in-memory record it returns.
vi.mock("./db", () => ({
  db: { insert: () => ({ values: () => ({ catch: () => {} }) }) },
}));

import { MemStorage } from "./storage";

function req(inputs: any) {
  return {
    workflowDefinition: { name: "WF", steps: { 0: { type: "data_input" }, 1: { type: "tool" } } },
    executionConfig: { mode: "sandbox" },
    inputs,
  } as any;
}

describe("createExecutionRun records resolved input bindings (provenance)", () => {
  let storage: MemStorage;
  beforeEach(() => { storage = new MemStorage(); });

  it("captures the exact dataset bound to each data-input step", async () => {
    const run = await storage.createExecutionRun(
      req([{ id: "ds-a", src: "hda", stepId: 0, name: "a.csv" }]),
      "user-1",
      "proj-1",
    );
    expect(run.inputBindings).toEqual([
      { stepId: "0", datasetId: "ds-a", src: "hda", name: "a.csv" },
    ]);
    // And it is retrievable from the in-memory record.
    const fetched = await storage.getExecutionRun(run.id);
    expect(fetched?.inputBindings).toEqual(run.inputBindings);
  });

  it("records an empty array when the run has no data inputs", async () => {
    const run = await storage.createExecutionRun(req(undefined), "user-1", "proj-1");
    expect(run.inputBindings).toEqual([]);
  });

  it("carries s3Uri/projectFileId provenance through to the record", async () => {
    const run = await storage.createExecutionRun(
      req([{ id: "pf-1", src: "project_file", stepId: 0, s3_uri: "s3://b/k.csv", project_file_id: "pf-1" }]),
      "user-1",
      "proj-1",
    );
    expect(run.inputBindings).toEqual([
      { stepId: "0", datasetId: "pf-1", src: "project_file", s3Uri: "s3://b/k.csv", projectFileId: "pf-1" },
    ]);
  });
});
