/**
 * L1 edge-case + L2 integration tests for Galaxy History agent context.
 *
 * Kept in a SEPARATE file from galaxy-assistant-history-block.test.ts because
 * auto-sync has stripped expansions of the latter twice in this session. New
 * file is the safer landing zone.
 *
 * Plan: docs/20260603_AGENT_HISTORY_TEST_PLAN.md
 * Implementation under test: frontend/server/galaxy-assistant.ts
 *   - _buildRecentRunsBlock (C2)
 *   - _toolListHistory (C1)
 *   - _toolListRunOutputs (C3)
 */
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("./storage", () => ({
  storage: {
    getExecutionRuns: vi.fn(),
    getExecutionRun: vi.fn(),
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

const getRuns = storage.getExecutionRuns as unknown as ReturnType<typeof vi.fn>;
const getRun = storage.getExecutionRun as unknown as ReturnType<typeof vi.fn>;

const mk = () =>
  new GalaxyAssistant({ anthropicApiKey: "sk-ant-test-key-placeholder" } as any) as any;

function runWith(overrides: any = {}) {
  return {
    id: "abcdef1234567890",
    workflowName: "demo-workflow",
    createdAt: new Date("2026-06-01T12:00:00Z"),
    execution: {
      status: "completed",
      startedAt: new Date("2026-06-01T12:00:00Z"),
      outputs: { a: "s3://x/a.csv" },
      parameters: { foo: 1 },
    },
    workflowDefinition: { parameters: {} },
    ...overrides,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// C2 — _buildRecentRunsBlock edge cases
// ─────────────────────────────────────────────────────────────────────────────
describe("C2 edge cases — _buildRecentRunsBlock", () => {
  beforeEach(() => getRuns.mockReset());

  it("uses createdAt when startedAt missing", async () => {
    getRuns.mockResolvedValue([
      runWith({
        createdAt: new Date("2026-05-15T08:00:00Z"),
        execution: { status: "completed", outputs: {}, parameters: {} },
      }),
    ]);
    const out = await mk()._buildRecentRunsBlock("u1");
    expect(out).toContain("2026-05-15");
  });

  it("renders 'recent' (not 'Invalid Date') when all timestamps missing", async () => {
    getRuns.mockResolvedValue([
      { id: "2".repeat(16), workflowName: "x", execution: { status: "completed", outputs: {} } } as any,
    ]);
    const out = await mk()._buildRecentRunsBlock("u1");
    expect(out).toContain("recent");
    expect(out).not.toContain("Invalid Date");
  });

  it("renders 'unnamed' when workflowName missing", async () => {
    getRuns.mockResolvedValue([runWith({ workflowName: undefined })]);
    expect(await mk()._buildRecentRunsBlock("u1")).toContain("unnamed");
  });

  it("renders 'unknown' when status missing", async () => {
    getRuns.mockResolvedValue([
      runWith({ execution: { outputs: {}, parameters: {} } }),
    ]);
    expect(await mk()._buildRecentRunsBlock("u1")).toContain("unknown");
  });

  it("treats null outputs as 0 (no crash)", async () => {
    getRuns.mockResolvedValue([
      runWith({ execution: { status: "running", outputs: null, parameters: {} } }),
    ]);
    expect(await mk()._buildRecentRunsBlock("u1")).toContain("0 outputs");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// C1 — _toolListHistory edge cases
// ─────────────────────────────────────────────────────────────────────────────
describe("C1 edge cases — _toolListHistory", () => {
  beforeEach(() => getRuns.mockReset());

  it("combines workflow_filter AND status_filter", async () => {
    getRuns.mockResolvedValue([
      runWith({ id: "a1", workflowName: "rnaseq-1", execution: { status: "completed", outputs: {} } }),
      runWith({ id: "a2", workflowName: "rnaseq-2", execution: { status: "failed", outputs: {} } }),
      runWith({ id: "a3", workflowName: "admet-1", execution: { status: "completed", outputs: {} } }),
    ]);
    const out = await mk()._toolListHistory(
      { workflow_filter: "rnaseq", status_filter: "completed" },
      { userId: "u1" }
    );
    expect((out as any).count).toBe(1);
    expect((out as any).runs[0].workflow).toBe("rnaseq-1");
  });

  it("returns count=0 when filter matches nothing", async () => {
    getRuns.mockResolvedValue([runWith({})]);
    const out = await mk()._toolListHistory(
      { workflow_filter: "nonexistent-xyz" },
      { userId: "u1" }
    );
    expect((out as any).count).toBe(0);
    expect((out as any).runs).toEqual([]);
  });

  it("caps paramKeys at 6 even with 20 params", async () => {
    const params = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`p${i}`, i]));
    getRuns.mockResolvedValue([
      runWith({ execution: { status: "completed", outputs: {}, parameters: params } }),
    ]);
    const out = await mk()._toolListHistory({}, { userId: "u1" });
    expect((out as any).runs[0].paramCount).toBe(20);
    expect((out as any).runs[0].paramKeys).toHaveLength(6);
  });

  it("falls back to workflowDefinition.parameters when execution.parameters absent", async () => {
    getRuns.mockResolvedValue([
      runWith({
        execution: { status: "completed", outputs: {} },
        workflowDefinition: { parameters: { wf_a: 1, wf_b: 2 } },
      }),
    ]);
    const out = await mk()._toolListHistory({}, { userId: "u1" });
    expect((out as any).runs[0].paramKeys).toContain("wf_a");
  });

  it("default limit is exactly 10 (regression for JS truthiness)", async () => {
    getRuns.mockResolvedValue(
      Array.from({ length: 30 }, (_, i) => runWith({ id: `id-${i}` }))
    );
    const out = await mk()._toolListHistory({}, { userId: "u1" });
    expect((out as any).count).toBe(10);
  });

  it("calls storage with (userId, undefined, undefined, 50) for overscan", async () => {
    getRuns.mockResolvedValue([]);
    await mk()._toolListHistory({}, { userId: "u1" });
    const args = getRuns.mock.calls[0];
    expect(args[0]).toBe("u1");
    expect(args[1]).toBeUndefined();
    expect(args[2]).toBeUndefined();
    expect(args[3]).toBe(50);
  });

  it("coerces numeric userId to string safely", async () => {
    getRuns.mockResolvedValue([]);
    await mk()._toolListHistory({}, { userId: 42 } as any);
    expect(getRuns.mock.calls[0][0]).toBe("42");
  });

  it("returns {error} on storage throw (non-fatal)", async () => {
    getRuns.mockImplementation(() => {
      throw new Error("transient db error");
    });
    const out = await mk()._toolListHistory({}, { userId: "u1" });
    expect((out as any).error).toMatch(/transient db error/);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// C3 — _toolListRunOutputs edge cases
// ─────────────────────────────────────────────────────────────────────────────
describe("C3 edge cases — _toolListRunOutputs", () => {
  beforeEach(() => getRun.mockReset());

  it("trims whitespace from run_id", async () => {
    getRun.mockResolvedValue({
      id: "abcdef1234567890",
      userId: "u1",
      execution: { status: "completed", outputs: { x: "s3://b/x.txt" } },
    });
    const out = await mk()._toolListRunOutputs(
      { run_id: "  abcdef1234567890  " },
      { userId: "u1" }
    );
    expect((out as any).runId).toBe("abcdef1234567890");
    expect(getRun.mock.calls[0][0]).toBe("abcdef1234567890");
  });

  it("no userId in context = admin access (returns any run)", async () => {
    getRun.mockResolvedValue({
      id: "rid",
      userId: "someone-else",
      execution: { status: "completed", outputs: { x: "s3://b/x.txt" } },
    });
    const out = await mk()._toolListRunOutputs({ run_id: "rid" }, {});
    expect((out as any).error).toBeUndefined();
    expect((out as any).count).toBe(1);
  });

  it("run with null userId = public, allowed from any user", async () => {
    getRun.mockResolvedValue({
      id: "rid",
      userId: null,
      execution: { status: "completed", outputs: { x: "s3://b/x.txt" } },
    });
    const out = await mk()._toolListRunOutputs({ run_id: "rid" }, { userId: "u1" });
    expect((out as any).error).toBeUndefined();
  });

  it("handles output value shapes: string, {path}, {s3_uri}, bare filename", async () => {
    getRun.mockResolvedValue({
      id: "rid",
      userId: "u1",
      execution: {
        status: "completed",
        outputs: {
          a: "s3://bucket/a.csv",
          b: { path: "s3://bucket/b.vcf" },
          c: { s3_uri: "s3://bucket/c.h5ad" },
          d: "just-a-filename.tsv",
        },
      },
    });
    const out = await mk()._toolListRunOutputs({ run_id: "rid" }, { userId: "u1" });
    const names = (out as any).files.map((f: any) => f.name);
    expect(names).toEqual(
      expect.arrayContaining(["a.csv", "b.vcf", "c.h5ad", "just-a-filename.tsv"])
    );
  });

  it("caps files array at 50 even when count is higher", async () => {
    const outputs = Object.fromEntries(
      Array.from({ length: 75 }, (_, i) => [`o${i}`, `s3://b/file${i}.csv`])
    );
    getRun.mockResolvedValue({
      id: "rid",
      userId: "u1",
      execution: { status: "completed", outputs },
    });
    const out = await mk()._toolListRunOutputs({ run_id: "rid" }, { userId: "u1" });
    expect((out as any).count).toBe(75);
    expect((out as any).files).toHaveLength(50);
  });

  it("returns {error} on storage throw (non-fatal)", async () => {
    getRun.mockImplementation(() => {
      throw new Error("db gone");
    });
    const out = await mk()._toolListRunOutputs({ run_id: "rid" }, { userId: "u1" });
    expect((out as any).error).toMatch(/db gone/);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// L2 integration — tool-surface contract
// ─────────────────────────────────────────────────────────────────────────────
describe("L2 — handler contract", () => {
  it("class exposes all three history-context methods with sane arity", async () => {
    const a = mk();
    expect(typeof a._toolListHistory).toBe("function");
    expect(typeof a._toolListRunOutputs).toBe("function");
    expect(typeof a._buildRecentRunsBlock).toBe("function");
    expect(a._toolListHistory.length).toBeGreaterThanOrEqual(2);
    expect(a._toolListRunOutputs.length).toBeGreaterThanOrEqual(2);
    expect(a._buildRecentRunsBlock.length).toBeGreaterThanOrEqual(1);
  });

  it("handlers all return Promises (async contract)", async () => {
    const a = mk();
    getRuns.mockResolvedValue([]);
    getRun.mockResolvedValue(undefined);
    expect(a._toolListHistory({}, {})).toBeInstanceOf(Promise);
    expect(a._toolListRunOutputs({ run_id: "x" }, {})).toBeInstanceOf(Promise);
    expect(a._buildRecentRunsBlock("u1")).toBeInstanceOf(Promise);
  });
});
