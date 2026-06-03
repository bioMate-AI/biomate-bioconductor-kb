/**
 * Unit tests for the async job-queue subsystem (Phase 0).
 *
 *   - dedup: two POSTs with the same dedup_key return the same jobId
 *   - recovery: orphan `running` rows from before boot are marked `failed`
 *
 * Both tests mock the `../db` module to avoid touching a real Postgres.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// ─── In-memory fake DB driver ─────────────────────────────────────────────
// We capture the executed SQL fragments and route them to a tiny row store.

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
let idCounter = 0;

function fakeExecute(query: any): { rows: any[] } {
  // drizzle queryChunks alternates: SQL fragments are objects whose `.value`
  // is a string-array; interpolated params appear as bare primitives (or
  // wrapped objects with scalar `.value`). We split:
  //   - object with array .value → SQL text
  //   - object with scalar .value → param
  //   - bare primitive            → param
  const chunks = (query?.queryChunks ?? []) as any[];
  const textParts: string[] = [];
  const params: any[] = [];
  for (const c of chunks) {
    if (c && typeof c === "object" && "value" in c) {
      if (Array.isArray(c.value)) {
        textParts.push(c.value.join(""));
      } else {
        params.push(c.value);
        textParts.push(" $? ");
      }
    } else {
      // bare value interpolated via sql`…${val}…`
      params.push(c);
      textParts.push(" $? ");
    }
  }
  const text = textParts.join("");

  const lower = text.toLowerCase();

  if (lower.includes("insert into download_jobs")) {
    // params: userId, kind, payloadJson, dedupKey
    const [userId, kind, payloadJson, dedupKey] = params;
    const row: FakeRow = {
      id: `job-${++idCounter}`,
      user_id: String(userId),
      kind: String(kind),
      payload: typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson,
      dedup_key: String(dedupKey),
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
    return { rows: [row] };
  }

  if (lower.includes("select * from download_jobs") && lower.includes("dedup_key")) {
    const dedupKey = params[0];
    const found = store
      .filter((r) => r.dedup_key === dedupKey && ["queued", "running", "ready"].includes(r.state))
      .sort((a, b) => b.created_at.getTime() - a.created_at.getTime());
    return { rows: found.length ? [found[0]] : [] };
  }

  if (lower.includes("select * from download_jobs") && lower.includes("where id")) {
    const id = params[0];
    const found = store.find((r) => r.id === id);
    return { rows: found ? [found] : [] };
  }

  if (lower.includes("select id, user_id, kind, payload, state from download_jobs")) {
    const id = params[0];
    const found = store.find((r) => r.id === id);
    return { rows: found ? [found] : [] };
  }

  if (lower.includes("select count(*)")) {
    const userId = params[0];
    const n = store.filter((r) => r.user_id === userId && ["queued", "running"].includes(r.state)).length;
    return { rows: [{ n }] };
  }

  if (lower.includes("update download_jobs") && lower.includes("set state = 'failed'") && lower.includes("where state = 'running'")) {
    // Recovery scan
    const reaped: FakeRow[] = [];
    for (const r of store) {
      if (r.state === "running") {
        r.state = "failed";
        r.error = "Server restarted during execution";
        reaped.push(r);
      }
    }
    return { rows: reaped.map((r) => ({ id: r.id })) };
  }

  if (lower.includes("update download_jobs")) {
    // Generic update — find by `where id =` last param.
    const id = params[params.length - 1];
    const row = store.find((r) => r.id === id);
    if (row) {
      if (lower.includes("set state = 'running'")) row.state = "running";
      if (lower.includes("set state = 'ready'")) row.state = "ready";
      if (lower.includes("set state = 'cancelled'")) row.state = "cancelled";
      if (lower.includes("set state = 'expired'")) row.state = "expired";
    }
    return { rows: [] };
  }

  return { rows: [] };
}

vi.mock("../../db", () => ({
  db: { execute: vi.fn(async (q: any) => fakeExecute(q)) },
  pool: {},
}));

// Stub auth so every request looks authed as user "u1".
vi.mock("../../auth-middleware", () => ({
  authenticateToken: (req: any, _res: any, next: any) => {
    req.user = { id: "u1" };
    next();
  },
}));

// Don't actually try to spawn handlers in dedup test.
vi.mock("../executor", async (importOriginal) => {
  const actual = (await importOriginal()) as any;
  return {
    ...actual,
    dispatch: vi.fn(() => {}),
    recoverOrphanRunningJobs: actual.recoverOrphanRunningJobs,
  };
});

beforeEach(() => {
  store = [];
  idCounter = 0;
});

afterEach(() => {
  vi.clearAllMocks();
});

describe("jobs router — dedup", () => {
  it("two POSTs with the same dedup_key return the same jobId", async () => {
    const express = (await import("express")).default;
    const { registerJobsRouter } = await import("../router");
    const app = express();
    registerJobsRouter(app);

    // Dep-free: bind app to an ephemeral port and use fetch.
    const http = await import("http");
    const server = http.createServer(app);
    await new Promise<void>((r) => server.listen(0, r));
    const addr = server.address() as any;
    const base = `http://127.0.0.1:${addr.port}`;
    try {
      const body = { kind: "download_all_zip_v0_stub", payload: { invocationId: "inv-1" } };
      const post = () => fetch(`${base}/api/jobs`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      const first = await post();
      const firstJson: any = await first.json();
      expect(first.status).toBe(201);
      expect(firstJson.jobId).toBeTruthy();

      const second = await post();
      const secondJson: any = await second.json();
      expect(second.status).toBe(200);
      expect(secondJson.jobId).toBe(firstJson.jobId);
    } finally {
      await new Promise<void>((r) => server.close(() => r()));
    }
  });
});

describe("executor — recovery scan", () => {
  it("marks orphan running rows as failed", async () => {
    // Seed a running row directly into the fake store.
    store.push({
      id: "job-orphan",
      user_id: "u1",
      kind: "download_all_zip_v0_stub",
      payload: {},
      dedup_key: "x",
      state: "running",
      progress: 50,
      eta_seconds: null,
      artifact_uri: null,
      artifact_bytes: null,
      error: null,
      created_at: new Date(),
      started_at: new Date(),
      ready_at: null,
      expires_at: null,
      cancelled_at: null,
    });

    const { recoverOrphanRunningJobs } = await import("../executor");
    const n = await recoverOrphanRunningJobs();
    expect(n).toBe(1);
    const row = store.find((r) => r.id === "job-orphan")!;
    expect(row.state).toBe("failed");
    expect(row.error).toBe("Server restarted during execution");
  });
});
