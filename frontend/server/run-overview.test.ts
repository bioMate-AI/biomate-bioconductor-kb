import { describe, expect, it, vi } from "vitest";
import type { ExecutionRun } from "@shared/schema";
import { buildRunOverviewRow, getExecutionRunsOverview } from "./run-overview";

function makeRun(overrides: Partial<ExecutionRun> = {}): ExecutionRun {
  const now = new Date("2026-03-03T12:00:00.000Z");
  return {
    id: overrides.id || "run-1",
    parentRunId: overrides.parentRunId,
    runSequence: overrides.runSequence ?? 1,
    userId: overrides.userId,
    projectId: overrides.projectId,
    chatSessionId: overrides.chatSessionId ?? "chat-1",
    mode: overrides.mode ?? "sandbox",
    workflowName: overrides.workflowName ?? "RNA Seq Pipeline",
    workflowDefinition: overrides.workflowDefinition,
    dataScope: overrides.dataScope ?? {
      fraction: 1,
      samplingStrategy: "random",
      sampledIds: [],
    },
    parameters: overrides.parameters ?? {
      version: 1,
      toolParameters: {},
    },
    execution: overrides.execution ?? {
      status: "running",
      executionEngine: "nextflow",
      nextflowStatus: {
        progressPercent: 42,
        log_tail: ["line 1", "line 2"],
        outputs: ["/tmp/results/a.tsv"],
      },
      galaxyInvocationId: "inv-1",
      nextflowRunId: "nf-1",
    },
    progress: overrides.progress ?? {
      totalSteps: 10,
      completedSteps: 4,
      percentComplete: 40,
    },
    steps: overrides.steps ?? [],
    metrics: overrides.metrics ?? {
      outputs: {
        fileCount: 0,
        totalSizeBytes: 0,
        byType: {},
        bySize: {},
      },
      runtime: {
        totalSeconds: 0,
        perStepSeconds: {},
      },
      resources: {
        peakMemoryGB: 0,
        avgCpuPercent: 0,
        diskUsedGB: 0,
      },
      quality: {},
    },
    interactions: overrides.interactions ?? [],
    recommendations: overrides.recommendations ?? [],
    comparison: overrides.comparison,
    createdAt: overrides.createdAt ?? now,
    updatedAt: overrides.updatedAt ?? now,
  };
}

describe("run-overview", () => {
  it("buildRunOverviewRow derives ids, progress, artifactReadiness and last log line", () => {
    const row = buildRunOverviewRow(makeRun());

    expect(row.runId).toBe("run-1");
    expect(row.progressPercent).toBe(42);
    expect(row.ids.galaxyInvocationId).toBe("inv-1");
    expect(row.ids.nextflowRunId).toBe("nf-1");
    expect(row.lastLogLine).toBe("line 2");
    expect(row.artifactReadiness?.hasOutputs).toBe(true);
    expect(row.artifactReadiness?.source).toBe("nextflow_status");
  });

  it("getExecutionRunsOverview applies scope, status/search filters, sort and pagination", async () => {
    const run1 = makeRun({
      id: "run-1",
      workflowName: "RNA Seq Pipeline",
      chatSessionId: "chat-1",
      execution: { status: "running" },
      createdAt: new Date("2026-03-03T10:00:00.000Z"),
      updatedAt: new Date("2026-03-03T10:10:00.000Z"),
    });
    const run2 = makeRun({
      id: "run-2",
      workflowName: "RNA Seq Iteration",
      chatSessionId: "chat-1",
      execution: { status: "failed" },
      createdAt: new Date("2026-03-03T09:00:00.000Z"),
      updatedAt: new Date("2026-03-03T09:10:00.000Z"),
    });
    const run3 = makeRun({
      id: "run-3",
      workflowName: "Metabolomics",
      chatSessionId: "chat-2",
      execution: { status: "running" },
    });

    const storage = {
      getExecutionRuns: vi.fn().mockResolvedValue([run1, run2, run3]),
    };

    const result = await getExecutionRunsOverview(storage, {
      userId: "user-1",
      scope: "current_chat",
      chatSessionId: "chat-1",
      status: "running,failed",
      search: "rna",
      sort: "createdAt:asc",
      limit: "1",
      offset: "0",
    });

    expect(storage.getExecutionRuns).toHaveBeenCalledWith(
      "user-1",
      undefined,
      undefined,
      5000,
      "chat-1"
    );
    expect(result.total).toBe(2);
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0].runId).toBe("run-2");
  });

  it("requires chatSessionId for current_chat scope", async () => {
    await expect(
      getExecutionRunsOverview(
        { getExecutionRuns: vi.fn().mockResolvedValue([]) },
        { scope: "current_chat" }
      )
    ).rejects.toThrow("chatSessionId is required when scope=current_chat");
  });
});
