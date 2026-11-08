import { describe, it, expect, vi } from "vitest";

// No real Postgres: persistence is fire-and-forget; the in-memory record is what is asserted.
vi.mock("./db", () => {
  const chain: any = { values: () => chain, set: () => chain, where: () => chain, catch: () => {} };
  return { db: { insert: () => chain, update: () => chain } };
});

import { MemStorage } from "./storage";

const req = { workflowDefinition: { name: "WF", steps: {} }, executionConfig: { mode: "sandbox" } } as any;

describe("updateExecutionRunStatus keeps a failed run's recorded error", () => {
  it("does not erase the failure summary when re-set to failed without a message", async () => {
    // The Nextflow terminal transition writes the summary, then the workflow_completed
    // handler calls updateExecutionRunStatus(id, 'failed') with no message.
    const s = new MemStorage();
    const run = await s.createExecutionRun(req, "u", "p");
    await s.updateExecutionRun(run.id, {
      execution: { ...run.execution, status: "failed", errorMessage: "Process X failed: OOM" },
    });
    const after = await s.updateExecutionRunStatus(run.id, "failed");
    expect(after?.execution.errorMessage).toBe("Process X failed: OOM");
  });

  it("an explicit message still replaces it, and a non-failed status clears it", async () => {
    const s = new MemStorage();
    const run = await s.createExecutionRun(req, "u", "p");
    await s.updateExecutionRun(run.id, { execution: { ...run.execution, status: "failed", errorMessage: "old" } });
    expect((await s.updateExecutionRunStatus(run.id, "failed", "new"))?.execution.errorMessage).toBe("new");
    expect((await s.updateExecutionRunStatus(run.id, "running"))?.execution.errorMessage).toBeUndefined();
  });
});
