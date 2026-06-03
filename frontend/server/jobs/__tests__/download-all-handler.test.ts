/**
 * Tests for the Phase 1 download_all_zip handler.
 *
 *   1) success: handler streams a non-empty ZIP into the artifact store and
 *      transitions the job row to `ready`
 *   2) cancellation: when checkCancelled() returns true mid-flight the job
 *      ends in `cancelled` state and the artifact is deleted
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Readable } from "stream";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

// ─── Fake DB (same shape as dedup.test.ts) ────────────────────────────────
interface FakeRow {
  id: string;
  user_id: string;
  kind: string;
  payload: any;
  dedup_key: string;
  state: string;
  progress: number;
  eta_seconds: number | null;
  artifact_uri: string | null;
  artifact_bytes: number | null;
  error: string | null;
  created_at: Date;
  started_at: Date | null;
  ready_at: Date | null;
  expires_at: Date | null;
  cancelled_at: Date | null;
}

let store: FakeRow[] = [];

function fakeExecute(query: any): { rows: any[] } {
  const chunks = (query?.queryChunks ?? []) as any[];
  const textParts: string[] = [];
  const params: any[] = [];
  for (const c of chunks) {
    if (c && typeof c === "object" && "value" in c) {
      if (Array.isArray(c.value)) textParts.push(c.value.join(""));
      else { params.push(c.value); textParts.push(" $? "); }
    } else {
      params.push(c); textParts.push(" $? ");
    }
  }
  const text = textParts.join("");
  const lower = text.toLowerCase();

  if (lower.includes("select id, user_id, kind, payload, state from download_jobs")) {
    const id = params[0];
    const found = store.find((r) => r.id === id);
    return { rows: found ? [found] : [] };
  }
  if (lower.includes("update download_jobs")) {
    const id = params[params.length - 1];
    const row = store.find((r) => r.id === id);
    if (row) {
      if (lower.includes("set state = 'running'")) row.state = "running";
      if (lower.includes("set state = 'ready'")) {
        row.state = "ready";
        // params order: progress=100, expiresAt, artifactUri, artifactBytes, id
        const uri = params[params.length - 3];
        const bytes = params[params.length - 2];
        row.artifact_uri = uri ?? null;
        row.artifact_bytes = bytes == null ? null : Number(bytes);
      }
      if (lower.includes("set state = 'cancelled'")) row.state = "cancelled";
      if (lower.includes("set state = 'failed'")) {
        row.state = "failed";
        row.error = String(params[0] ?? "failed");
      }
      if (lower.includes("set progress = ")) {
        row.progress = Number(params[0]);
      }
    }
    return { rows: [] };
  }
  return { rows: [] };
}

vi.mock("../../db", () => ({
  db: { execute: vi.fn(async (q: any) => fakeExecute(q)) },
  pool: {},
}));

// Mock storage with two outputs.
const mockOutputs = [
  { id: "o1", name: "report", extension: "txt", galaxyDatasetId: "d1", metadata: {}, size: 11 },
  { id: "o2", name: "table",  extension: "tsv", galaxyDatasetId: "d2", metadata: {}, size: 5 },
];
vi.mock("../../storage", () => ({
  storage: {
    getInvocation: vi.fn(async (id: string) => ({
      id,
      workflowName: "TestWF",
    })),
    getInvocationByGalaxyId: vi.fn(async () => null),
    getInvocationOutputs: vi.fn(async () => mockOutputs),
  },
}));

// Mock GalaxyAPIProxy so downloadDataset returns a small in-memory stream.
vi.mock("../../galaxy-api-proxy", () => {
  class GalaxyAPIProxy {
    async downloadDataset(id: string) {
      return Readable.from([Buffer.from(`payload-for-${id}`)]);
    }
  }
  return { GalaxyAPIProxy };
});

let tmpDir: string;

beforeEach(() => {
  store = [];
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "biomate-jobtest-"));
  process.env.BIOMATE_ARTIFACT_DIR = tmpDir;
  vi.resetModules();
});

afterEach(() => {
  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
  vi.clearAllMocks();
});

function seedQueuedJob(): FakeRow {
  const row: FakeRow = {
    id: "job-test-1",
    user_id: "u1",
    kind: "download_all_zip",
    payload: { invocationId: "inv-xyz" },
    dedup_key: "download_all_zip:inv-xyz",
    state: "queued",
    progress: 0,
    eta_seconds: null,
    artifact_uri: null,
    artifact_bytes: null,
    error: null,
    created_at: new Date(),
    started_at: null,
    ready_at: null,
    expires_at: null,
    cancelled_at: null,
  };
  store.push(row);
  return row;
}

async function waitFor(pred: () => boolean, timeoutMs = 5000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (pred()) return;
    await new Promise((r) => setTimeout(r, 20));
  }
  throw new Error("waitFor: timeout");
}

describe("download_all_zip handler", () => {
  it("produces a non-empty artifact and transitions to ready", async () => {
    // Importing the handler module registers the kind on the executor.
    await import("../handlers/download-all-zip");
    const { dispatch } = await import("../executor");

    const row = seedQueuedJob();
    dispatch(row.id);

    await waitFor(() => row.state === "ready" || row.state === "failed");
    expect(row.state).toBe("ready");
    expect(row.artifact_bytes ?? 0).toBeGreaterThan(0);

    const artifactPath = path.join(tmpDir, row.id);
    expect(fs.existsSync(artifactPath)).toBe(true);
    expect(fs.statSync(artifactPath).size).toBeGreaterThan(0);
    // ZIP local-file-header magic
    const head = fs.readFileSync(artifactPath).subarray(0, 2);
    expect(head[0]).toBe(0x50);
    expect(head[1]).toBe(0x4b);
  });

  it("ends in cancelled state and deletes the artifact when cancelled mid-flight", async () => {
    await import("../handlers/download-all-zip");
    const executor = await import("../executor");

    const row = seedQueuedJob();
    // Pre-set the cancellation flag so the very first checkCancelled() inside
    // the handler's per-output loop returns true.
    executor.signalCancel(row.id);
    executor.dispatch(row.id);

    await waitFor(() => row.state === "cancelled" || row.state === "ready" || row.state === "failed");
    expect(row.state).toBe("cancelled");

    // Give the executor a tick to perform store.delete(jobId) after the
    // handler returns — delete is sync but happens after a `flushProgress`
    // await on the cancellation branch.
    await new Promise((r) => setTimeout(r, 50));
    const artifactPath = path.join(tmpDir, row.id);
    if (fs.existsSync(artifactPath)) {
      // Surface the actual dir contents for diagnostics if this still fails.
      const listing = fs.readdirSync(tmpDir);
      throw new Error(`Expected artifact at ${artifactPath} to be deleted; tmpDir contents: ${JSON.stringify(listing)}`);
    }
    expect(fs.existsSync(artifactPath)).toBe(false);
  });
});
