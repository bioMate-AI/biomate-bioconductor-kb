import { describe, expect, it } from "vitest";
import {
  isHarnessTerminalStatus,
  normalizeRunsListResponse,
  pickRunIdFromExecuteResponse,
  pickRunIdFromRunRow,
  pickRunIdFromSessionPayload,
} from "./coldstart-run-id";

describe("normalizeRunsListResponse", () => {
  it("accepts bare array from GET /api/workflows/runs", () => {
    expect(normalizeRunsListResponse([{ id: "a" }, { id: "b" }])).toEqual([
      { id: "a" },
      { id: "b" },
    ]);
  });

  it("accepts {runs}/{items}/{data} wrappers", () => {
    expect(normalizeRunsListResponse({ runs: [{ id: "r1" }] })[0].id).toBe("r1");
    expect(normalizeRunsListResponse({ items: [{ id: "i1" }] })[0].id).toBe("i1");
    expect(normalizeRunsListResponse({ data: [{ id: "d1" }] })[0].id).toBe("d1");
  });

  it("returns [] for junk", () => {
    expect(normalizeRunsListResponse(null)).toEqual([]);
    expect(normalizeRunsListResponse({})).toEqual([]);
    expect(normalizeRunsListResponse("x")).toEqual([]);
  });
});

describe("pickRunIdFromRunRow / execute / session", () => {
  it("picks id aliases from a run row", () => {
    expect(pickRunIdFromRunRow({ id: "uuid-1" })).toBe("uuid-1");
    expect(pickRunIdFromRunRow({ run_id: "nf-1" })).toBe("nf-1");
    expect(pickRunIdFromRunRow({ runId: "r" })).toBe("r");
    expect(pickRunIdFromRunRow({})).toBeUndefined();
  });

  it("picks execute / chain response keys", () => {
    expect(pickRunIdFromExecuteResponse({ runId: "e1" })).toBe("e1");
    expect(pickRunIdFromExecuteResponse({ chain_run_id: "c1" })).toBe("c1");
    expect(pickRunIdFromExecuteResponse({ run_id: "n1" })).toBe("n1");
  });

  it("reads message metadata then workflows backfill", () => {
    expect(
      pickRunIdFromSessionPayload({
        messages: [
          { role: "assistant", metadata: { workflow: { name: "x" } } },
          { role: "assistant", metadata: { runId: "from-meta" } },
        ],
      }),
    ).toBe("from-meta");

    expect(
      pickRunIdFromSessionPayload({
        messages: [],
        workflows: [{ workflow_id: "from-backfill", workflow_name: "W" }],
      }),
    ).toBe("from-backfill");

    expect(
      pickRunIdFromSessionPayload({
        messages: [{ metadata: { workflow: { chain_run_id: "chain-9" } } }],
      }),
    ).toBe("chain-9");
  });
});

describe("isHarnessTerminalStatus", () => {
  it("treats paused as terminal for measurement (QC gate)", () => {
    expect(isHarnessTerminalStatus("paused")).toBe(true);
    expect(isHarnessTerminalStatus("completed")).toBe(true);
    expect(isHarnessTerminalStatus("running")).toBe(false);
    expect(isHarnessTerminalStatus("idle")).toBe(false);
  });
});
