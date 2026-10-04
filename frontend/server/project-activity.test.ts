/**
 * Project activity ledger (Team workspace Phase 1) — route BEHAVIOUR tests.
 *
 * Mounts the real `registerProjectRoutes` handler on an express app and drives
 * it over a real (loopback) HTTP request, with the DB + auth + memory seams
 * faked. Asserts STATUS + BODY so an inverted ownership check (cross-user
 * leak), a missing recordProjectActivity() call, or a wrong sort FAILS the
 * suite — not a source grep.
 *
 * Seams faked (our own code, never a real Postgres):
 *   - ./db             pool.query → a tiny in-memory fake that dispatches on
 *                      SQL text and actually persists project_activity rows,
 *                      so "recorded on mutation → visible in the feed" is a
 *                      genuine round-trip.
 *   - ./auth-middleware authenticateToken → pass-through; req.user set by a
 *                      preceding middleware from a per-test `currentUser`.
 *   - ./memory-repository memoryService.projects.getProject (+ ensureLtmUser)
 *                      — drives ownership.
 *   - ./s3-client       s3Service — not exercised by these flows; stubbed so
 *                      no S3 client is constructed at import.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express, { type Express } from "express";
import type { Server } from "http";

const httpFetch = globalThis.fetch;

// ─── In-memory activity store + SQL-dispatching fake pool ─────────────────────
interface ActivityRow {
  id: string;
  project_id: string;
  actor_user_id: string | null;
  event_type: string;
  payload: Record<string, unknown>;
  created_at: string;
}
let activityRows: ActivityRow[] = [];
// Membership probe result for _isOwnerOrMember's `SELECT 1 FROM project_members`.
let membershipRows: Array<Record<string, unknown>> = [];
// Invitee returned by the `SELECT ... FROM users WHERE email` lookup.
let inviteeRow: { id: string; email: string; fullName: string } | null = null;
let seq = 0;

async function fakeQuery(text: string, params: any[] = []): Promise<any> {
  const t = text.replace(/\s+/g, " ").trim();

  // Append-only ledger write (recordProjectActivity).
  if (t.startsWith("INSERT INTO project_activity")) {
    seq += 1;
    activityRows.push({
      id: `act-${seq}`,
      project_id: params[0],
      actor_user_id: params[1] ?? null,
      event_type: params[2],
      payload: JSON.parse(params[3] ?? "{}"),
      // Monotonic so newest-first ordering is unambiguous.
      created_at: new Date(1_700_000_000_000 + seq).toISOString(),
    });
    return { rows: [], rowCount: 1 };
  }

  // Ledger read (GET /activity): params = [projectId, limit+1, offset].
  if (/FROM project_activity/.test(t)) {
    const [pid, lim, off] = params as [string, number, number];
    // Rows are pushed in chronological order → reverse for newest-first.
    const all = activityRows.filter((r) => r.project_id === pid).slice().reverse();
    const page = all.slice(off, off + lim).map((r) => ({ ...r, actor_email: null, actorName: null }));
    return { rows: page, rowCount: page.length };
  }

  // Invitee lookup for POST /members.
  if (/FROM users WHERE email/.test(t)) {
    return inviteeRow ? { rows: [inviteeRow], rowCount: 1 } : { rows: [], rowCount: 0 };
  }

  // Membership mutations — treat as a single affected row. Checked BEFORE the
  // SELECT probe because `DELETE FROM project_members WHERE project_id …` also
  // contains the probe's substring.
  if (/^INSERT INTO project_members/.test(t)) return { rows: [], rowCount: 1 };
  if (/^UPDATE project_members/.test(t)) return { rows: [], rowCount: 1 };
  if (/^DELETE FROM project_members/.test(t)) return { rows: [], rowCount: 1 };

  // _isOwnerOrMember / _getUserRole membership probe (SELECT ... FROM project_members).
  if (/FROM project_members WHERE project_id/.test(t)) {
    return { rows: membershipRows, rowCount: membershipRows.length };
  }

  // Module-init DDL + anything else.
  return { rows: [], rowCount: 0 };
}

const fakeProjects = {
  getProject: vi.fn(),
};
const ensureLtmUser = vi.fn().mockResolvedValue(undefined);

vi.mock("./db", () => ({
  pool: { query: (text: string, params?: any[]) => fakeQuery(text, params) },
}));
vi.mock("./auth-middleware", () => ({
  authenticateToken: (_req: any, _res: any, next: any) => next(),
}));
vi.mock("./memory-repository", () => ({
  memoryService: { projects: fakeProjects, ensureLtmUser: (...a: any[]) => ensureLtmUser(...a) },
}));
vi.mock("./s3-client", () => ({
  s3Service: {
    putObject: vi.fn(),
    deleteFile: vi.fn(),
    generatePresignedDownloadUrl: vi.fn(),
  },
}));

let app: Express;
let server: Server;
let baseUrl = "";
let currentUser: { id: string; subscriptionTier?: string } | null = null;

beforeAll(async () => {
  const { registerProjectRoutes } = await import("./project-routes");
  app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    if (currentUser) (req as any).user = currentUser;
    next();
  });
  registerProjectRoutes(app);
  await new Promise<void>((r) => {
    server = app.listen(0, "127.0.0.1", () => r());
  });
  const { port } = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${port}`;
});

afterAll(() => {
  server?.close();
});

beforeEach(() => {
  vi.clearAllMocks();
  activityRows = [];
  membershipRows = [];
  inviteeRow = null;
  seq = 0;
  currentUser = { id: "owner-1" };
});

async function get(path: string) {
  const r = await httpFetch(`${baseUrl}${path}`);
  const body = await r.json().catch(() => ({}));
  return { status: r.status, body };
}
async function post(path: string, payload: unknown = {}) {
  const r = await httpFetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const body = await r.json().catch(() => ({}));
  return { status: r.status, body };
}

describe("project activity ledger — event recorded on a membership change", () => {
  it("owner adds a member → 201 AND a member_added event is recorded", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    inviteeRow = { id: "invitee-9", email: "new@x.io", fullName: "New Person" };

    const { status } = await post("/api/projects/p1/members", { email: "new@x.io", role: "editor" });
    expect(status).toBe(201);

    // The primary mutation recorded exactly one attributed, server-rendered event.
    expect(activityRows).toHaveLength(1);
    const ev = activityRows[0];
    expect(ev.event_type).toBe("member_added");
    expect(ev.project_id).toBe("p1");
    expect(ev.actor_user_id).toBe("owner-1");
    expect(ev.payload).toEqual({ targetUserId: "invitee-9", role: "editor" });
    // No secrets / raw content leaked into the payload (plan §3 allowlist).
    const payloadStr = JSON.stringify(ev.payload);
    expect(payloadStr).not.toMatch(/token|password|secret|s3_key|https?:\/\//i);
  });

  it("owner changes a member role → role_changed event attributed to the owner", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });

    const r = await httpFetch(`${baseUrl}/api/projects/p1/members/invitee-9`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ role: "viewer" }),
    });
    expect(r.status).toBe(200);

    expect(activityRows).toHaveLength(1);
    expect(activityRows[0].event_type).toBe("role_changed");
    expect(activityRows[0].payload).toEqual({ targetUserId: "invitee-9", role: "viewer" });
  });
});

describe("project activity ledger — GET /api/projects/:id/activity authorization", () => {
  it("non-member → 404 (never leak existence, never enumerate the feed)", async () => {
    // Project exists but is owned by someone else, and the caller is not a member.
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "other-99", name: "P" });
    membershipRows = [];
    currentUser = { id: "outsider-7" };
    // Even if events exist, an outsider must not see them.
    activityRows.push({
      id: "act-x", project_id: "p1", actor_user_id: "other-99",
      event_type: "member_added", payload: {}, created_at: new Date().toISOString(),
    });

    const { status, body } = await get("/api/projects/p1/activity");
    expect(status).toBe(404);
    expect(status).not.toBe(403);
    expect(body.error).toMatch(/not found/i);
    expect(body.activity).toBeUndefined();
  });

  it("unauthenticated → 401", async () => {
    currentUser = null;
    const { status } = await get("/api/projects/p1/activity");
    expect(status).toBe(401);
    expect(fakeProjects.getProject).not.toHaveBeenCalled();
  });
});

describe("project activity ledger — GET returns the recorded events", () => {
  it("owner sees the events newest-first after mutations", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    inviteeRow = { id: "invitee-9", email: "new@x.io", fullName: "New Person" };

    // Two mutations in order → two ledger rows.
    await post("/api/projects/p1/members", { email: "new@x.io", role: "viewer" });
    await httpFetch(`${baseUrl}/api/projects/p1/members/invitee-9`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ role: "editor" }),
    });

    const { status, body } = await get("/api/projects/p1/activity");
    expect(status).toBe(200);
    expect(Array.isArray(body.activity)).toBe(true);
    expect(body.activity).toHaveLength(2);
    // Newest first: the role change was recorded after the add.
    expect(body.activity[0].event_type).toBe("role_changed");
    expect(body.activity[1].event_type).toBe("member_added");
    expect(body.hasMore).toBe(false);
  });

  it("a member (non-owner) can also read the feed", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    membershipRows = [{ role: "viewer" }]; // caller is a member
    currentUser = { id: "member-2" };
    activityRows.push({
      id: "act-1", project_id: "p1", actor_user_id: "owner-1",
      event_type: "file_added", payload: { fileId: "f1" },
      created_at: new Date(1_700_000_000_000).toISOString(),
    });

    const { status, body } = await get("/api/projects/p1/activity");
    expect(status).toBe(200);
    expect(body.activity).toHaveLength(1);
    expect(body.activity[0].event_type).toBe("file_added");
  });

  it("respects limit and reports hasMore when more rows exist", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    for (let i = 0; i < 3; i++) {
      await fakeQuery("INSERT INTO project_activity (project_id, actor_user_id, event_type, payload) VALUES ($1,$2,$3,$4::jsonb)",
        ["p1", "owner-1", "plan_created", JSON.stringify({ planId: `pl-${i}` })]);
    }
    const { status, body } = await get("/api/projects/p1/activity?limit=2");
    expect(status).toBe(200);
    expect(body.activity).toHaveLength(2);
    expect(body.limit).toBe(2);
    expect(body.hasMore).toBe(true);
  });
});
