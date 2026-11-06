/**
 * report-version-store — the DB-backed store around the pure report-version
 * model (Task #22 / L5). Mirrors report-version.test.ts patterns but exercises
 * the persistence + single-writer behaviour by stubbing `storage`:
 *   - first save seeds the immutable run original (v0) from the current markdown
 *   - append forks a new version that KEEPS the runId and is content-addressable
 *   - the run original stays immutable across appends
 *   - content round-trips (list/get return the persisted body)
 *   - concurrent appends serialize (no lost update, monotonically numbered)
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { sha256Hex } from "./reproducibility-record";

// In-memory fake of the execution_runs row that updateExecutionRun/getExecutionRun
// touch. The store only reads/writes `execution.reportVersions`, so this is enough.
const _rows = new Map<string, any>();

vi.mock("./storage", () => ({
  storage: {
    async getExecutionRun(id: string) {
      return _rows.get(id);
    },
    async getExecutionRunByGalaxyId(gid: string) {
      for (const r of _rows.values()) {
        if (r?.execution?.galaxyInvocationId === gid) return r;
      }
      return undefined;
    },
    async updateExecutionRun(id: string, updates: any) {
      const existing = _rows.get(id) || { id, execution: {} };
      const next = { ...existing, ...updates, id, execution: { ...existing.execution, ...updates.execution } };
      _rows.set(id, next);
      return next;
    },
  },
}));

// Import AFTER the mock is registered.
import { reportVersionStore } from "./report-version-store";

function seedRun(id: string, execution: any = {}) {
  _rows.set(id, { id, workflowName: "wf", execution });
}

describe("report-version-store (L5 — versioned run report, persisted, single writer)", () => {
  beforeEach(() => {
    _rows.clear();
  });

  it("append seeds an immutable run original (v0) from the current markdown, then forks v1", async () => {
    seedRun("run-1");
    const v1 = await reportVersionStore.append("run-1", "edited body", {
      note: "tightened abstract",
      currentMarkdown: "ORIGINAL report body",
    });
    expect(v1).not.toBeNull();
    expect(v1!.version).toBe(1);
    expect(v1!.runId).toBe("run-1");
    expect(v1!.editedFromVersion).toBe(0);
    expect(v1!.note).toBe("tightened abstract");
    expect(v1!.immutable).toBe(false);
    expect(v1!.content).toBe("edited body");
    expect(v1!.sha256).toBe(sha256Hex("edited body"));

    const list = await reportVersionStore.list("run-1");
    expect(list).toHaveLength(2);
    const [orig, edit] = list!;
    expect(orig.version).toBe(0);
    expect(orig.immutable).toBe(true);
    expect(orig.runId).toBe("run-1"); // back-link on the original
    expect(orig.content).toBe("ORIGINAL report body");
    expect(orig.sha256).toBe(sha256Hex("ORIGINAL report body"));
    expect(edit.version).toBe(1);
  });

  it("ensureOriginal is idempotent — the run original is immutable across calls", async () => {
    seedRun("run-2");
    const o1 = await reportVersionStore.ensureOriginal("run-2", "first markdown");
    const o2 = await reportVersionStore.ensureOriginal("run-2", "DIFFERENT markdown");
    expect(o1!.version).toBe(0);
    expect(o2!.version).toBe(0);
    // Second call must NOT overwrite the original body/hash.
    expect(o2!.content).toBe("first markdown");
    expect(o2!.sha256).toBe(sha256Hex("first markdown"));
    const list = await reportVersionStore.list("run-2");
    expect(list).toHaveLength(1);
    expect(list![0].immutable).toBe(true);
  });

  it("multiple appends stay append-only and monotonically numbered; v0 untouched", async () => {
    seedRun("run-3");
    await reportVersionStore.append("run-3", "v1", { currentMarkdown: "orig" });
    await reportVersionStore.append("run-3", "v2");
    const v3 = await reportVersionStore.append("run-3", "v3");
    expect(v3!.version).toBe(3);
    expect(v3!.editedFromVersion).toBe(2);
    expect(v3!.runId).toBe("run-3");
    const list = await reportVersionStore.list("run-3");
    expect(list!.map((v) => v.version)).toEqual([0, 1, 2, 3]);
    expect(list![0].content).toBe("orig"); // original body preserved
    expect(list![0].immutable).toBe(true);
    expect(list![3].content).toBe("v3");
  });

  it("get returns a specific version's content and metadata", async () => {
    seedRun("run-4");
    await reportVersionStore.append("run-4", "the edit", { currentMarkdown: "the original" });
    const v0 = await reportVersionStore.get("run-4", 0);
    const v1 = await reportVersionStore.get("run-4", 1);
    expect(v0!.content).toBe("the original");
    expect(v1!.content).toBe("the edit");
    expect(await reportVersionStore.get("run-4", 99)).toBeNull();
  });

  it("resolves by galaxy invocation id, not just the primary key", async () => {
    seedRun("run-5", { galaxyInvocationId: "gx-abc" });
    const v1 = await reportVersionStore.append("gx-abc", "body", { currentMarkdown: "orig" });
    expect(v1!.runId).toBe("run-5"); // back-link is the primary key, not the galaxy id
    const list = await reportVersionStore.list("gx-abc");
    expect(list).toHaveLength(2);
  });

  it("concurrent appends serialize (single writer) — no lost update", async () => {
    seedRun("run-6");
    const results = await Promise.all([
      reportVersionStore.append("run-6", "a", { currentMarkdown: "orig" }),
      reportVersionStore.append("run-6", "b", { currentMarkdown: "orig" }),
      reportVersionStore.append("run-6", "c", { currentMarkdown: "orig" }),
    ]);
    const nums = results.map((r) => r!.version).sort((a, b) => a - b);
    expect(nums).toEqual([1, 2, 3]); // all three appended, none lost
    const list = await reportVersionStore.list("run-6");
    expect(list!.map((v) => v.version)).toEqual([0, 1, 2, 3]);
    // exactly one immutable original
    expect(list!.filter((v) => v.immutable)).toHaveLength(1);
  });

  it("returns null for an unknown run (never throws)", async () => {
    expect(await reportVersionStore.list("nope")).toBeNull();
    expect(await reportVersionStore.get("nope", 0)).toBeNull();
    expect(await reportVersionStore.append("nope", "x")).toBeNull();
    expect(await reportVersionStore.ensureOriginal("nope", "x")).toBeNull();
  });
});
