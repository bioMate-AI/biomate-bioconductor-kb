/**
 * C1+C2 regression tests — Galaxy History context for the agent.
 *
 * These verify the shape of the recent-runs prompt block and the
 * list_history tool output. They mock the storage layer; no DB needed.
 *
 * See docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md.
 */
import { describe, expect, it, vi, beforeEach } from "vitest";

// Mock storage + Anthropic SDK (SDK blocks construction in browser-like envs)
vi.mock("./storage", () => ({
  storage: {
    getExecutionRuns: vi.fn(),
  },
}));
vi.mock("@anthropic-ai/sdk", () => ({
  default: class Anthropic {
    messages = { create: vi.fn(), stream: vi.fn() };
  },
}));
vi.mock("@google/generative-ai", () => ({
  GoogleGenerativeAI: class {
    getGenerativeModel() {
      return { generateContent: vi.fn(), generateContentStream: vi.fn() };
    }
  },
}));

import { storage } from "./storage";
import { GalaxyAssistant } from "./galaxy-assistant";

const mockedGetRuns = storage.getExecutionRuns as unknown as ReturnType<typeof vi.fn>;

function makeRun(overrides: any) {
  return {
    id: "abcdef1234567890",
    workflowName: "ode-signaling-simulation",
    createdAt: new Date("2026-06-01T12:00:00Z"),
    execution: {
      status: "completed",
      startedAt: new Date("2026-06-01T12:00:00Z"),
      outputs: { plot: "s3://x/plot.png", csv: "s3://x/data.csv" },
      parameters: { drug_name: "aspirin", target_node: "AKT1" },
    },
    workflowDefinition: { parameters: {} },
    ...overrides,
  };
}

describe("C2 — recent-runs prompt block", () => {
  beforeEach(() => {
    mockedGetRuns.mockReset();
  });

  it("returns empty string when user has no runs", async () => {
    mockedGetRuns.mockResolvedValue([]);
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._buildRecentRunsBlock("user-1");
    expect(out).toBe("");
  });

  it("renders a tight one-line-per-run block with id, name, status, outputs", async () => {
    mockedGetRuns.mockResolvedValue([
      makeRun({ id: "abcdef1234567890" }),
      makeRun({
        id: "11112222deadbeef",
        workflowName: "cpa-synergy-gpu",
        execution: {
          status: "failed",
          startedAt: new Date("2026-06-02T08:00:00Z"),
          outputs: {},
          parameters: {},
        },
      }),
    ]);
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._buildRecentRunsBlock("user-1");
    expect(out).toContain("Your recent workflow runs");
    expect(out).toContain("abcdef12");
    expect(out).toContain("ode-signaling-simulation");
    expect(out).toContain("completed");
    expect(out).toContain("2 outputs");
    expect(out).toContain("11112222");
    expect(out).toContain("failed");
    expect(out).toContain("call list_history");
  });

  it("never throws on storage failure (non-fatal injection)", async () => {
    mockedGetRuns.mockRejectedValue(new Error("db down"));
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    await expect(a._buildRecentRunsBlock("user-1")).resolves.toBe("");
  });

  it("requests last 5 runs only (prompt-budget guardrail)", async () => {
    mockedGetRuns.mockResolvedValue([]);
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    await a._buildRecentRunsBlock("user-1");
    const args = mockedGetRuns.mock.calls[0];
    // signature: (userId, projectId, mode, limit, chatSessionId)
    expect(args[0]).toBe("user-1");
    expect(args[3]).toBe(5);
  });
});

describe("C1 — list_history tool handler", () => {
  beforeEach(() => mockedGetRuns.mockReset());

  it("returns runs without userId guard noise when userId present", async () => {
    mockedGetRuns.mockResolvedValue([makeRun({})]);
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._toolListHistory({ limit: 3 }, { userId: "u1" } as any);
    expect((out as any).count).toBe(1);
    expect((out as any).runs[0].id).toBe("abcdef12");
    expect((out as any).runs[0].workflow).toBe("ode-signaling-simulation");
    expect((out as any).runs[0].paramKeys).toContain("drug_name");
    expect((out as any).runs[0].outputCount).toBe(2);
  });

  it("filters by workflow substring (case-insensitive)", async () => {
    mockedGetRuns.mockResolvedValue([
      makeRun({ id: "aaa1", workflowName: "rnaseq-deseq2" }),
      makeRun({ id: "bbb2", workflowName: "cryosparc-spa" }),
    ]);
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._toolListHistory(
      { workflow_filter: "RNA" },
      { userId: "u1" } as any
    );
    expect((out as any).count).toBe(1);
    expect((out as any).runs[0].workflow).toBe("rnaseq-deseq2");
  });

  it("filters by status", async () => {
    mockedGetRuns.mockResolvedValue([
      makeRun({ id: "aaa1", execution: { status: "completed", outputs: {} } }),
      makeRun({ id: "bbb2", execution: { status: "failed", outputs: {} } }),
    ]);
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._toolListHistory(
      { status_filter: "failed" },
      { userId: "u1" } as any
    );
    expect((out as any).count).toBe(1);
    expect((out as any).runs[0].status).toBe("failed");
  });

  it("clamps limit to [1, 25]", async () => {
    mockedGetRuns.mockResolvedValue(Array.from({ length: 50 }, (_, i) => makeRun({ id: `id${i.toString().padStart(8, "0")}` })));
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._toolListHistory({ limit: 999 }, { userId: "u1" } as any);
    expect((out as any).count).toBe(25);
    const out2 = await a._toolListHistory({ limit: 0 }, { userId: "u1" } as any);
    expect((out2 as any).count).toBe(1);
  });

  it("returns explanatory note when userId missing (no DB call)", async () => {
    const a = new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;
    const out = await a._toolListHistory({}, {} as any);
    expect((out as any).runs).toEqual([]);
    expect((out as any).note).toMatch(/no userId/);
    expect(mockedGetRuns).not.toHaveBeenCalled();
  });
});
