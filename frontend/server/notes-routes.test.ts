/**
 * Project Notes (synthesis) route BEHAVIOUR tests.
 *
 * These mount the real `registerNotesRoutes` handler on an express app
 * and drive it over a real (loopback) HTTP request, with the repo + LLM
 * seams faked. They assert STATUS + BODY — so an inverted ownership
 * check (cross-user leak), a reversed `createdAt` sort, or a collapsed
 * 502/500 distinction FAILS the suite. (The prior version was 100%
 * `SRC.match(regex)` source-grep and caught none of these — see
 * docs/20260909_UPGRADE_TEST_QUALITY_AUDIT.md gap #1.)
 *
 * Seams faked (our own code, never a real DB / real Gemini):
 *   - ./auth-middleware  authenticateToken → pass-through; req.user is
 *     set by a preceding middleware from a per-test `currentUser`.
 *   - ./gemini-flash     callGeminiFlash → vi.fn we script per test.
 *   - ./memory-repository memoryService.projects.{getProject,
 *     getProjectKnowledge,addProjectKnowledge,loadProjectContext}.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express, { type Express } from "express";
import type { Server } from "http";

// Capture the real fetch BEFORE any global stubbing so we can talk to
// our own test server. (notes-routes makes no outbound fetch, but we
// keep the same discipline as evidence-routes.test.ts.)
const httpFetch = globalThis.fetch;

// ─── Fakes wired through vi.mock ──────────────────────────────────────
const fakeProjects = {
  getProject: vi.fn(),
  getProjectKnowledge: vi.fn(),
  addProjectKnowledge: vi.fn(),
  loadProjectContext: vi.fn(),
};
const callGeminiFlash = vi.fn();

vi.mock("./auth-middleware", () => ({
  // Pass-through: the real middleware calls next() when req.user is
  // already set, which our test middleware does below.
  authenticateToken: (_req: any, _res: any, next: any) => next(),
}));
vi.mock("./memory-repository", () => ({
  memoryService: { projects: fakeProjects },
}));
vi.mock("./gemini-flash", () => ({
  callGeminiFlash: (...args: any[]) => callGeminiFlash(...args),
}));

let app: Express;
let server: Server;
let baseUrl = "";
// Per-test authenticated user (or null for the unauth case).
let currentUser: { id: string } | null = null;

beforeAll(async () => {
  const { registerNotesRoutes } = await import("./notes-routes");
  app = express();
  app.use(express.json());
  // Stand in for the auth layer: attach req.user from currentUser.
  app.use((req, _res, next) => {
    if (currentUser) (req as any).user = currentUser;
    next();
  });
  registerNotesRoutes(app);
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

describe("notes-routes — GET /api/projects/:id/notes", () => {
  it("owner with rows → 200 and returns the NEWEST synthesis first", async () => {
    // Ownership passes.
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    // Two rows, both relevanceScore 1.0 (so a relevance sort can't
    // disambiguate). The handler MUST pick by createdAt desc. The rows
    // are deliberately fed OLDEST-first so a missing/forward sort would
    // return the older row and this test would fail.
    const older = {
      id: "n-old",
      content: "old brief",
      createdAt: "2026-01-01T00:00:00.000Z",
      relevanceScore: 1.0,
    };
    const newer = {
      id: "n-new",
      content: "new brief",
      createdAt: "2026-09-01T00:00:00.000Z",
      relevanceScore: 1.0,
    };
    fakeProjects.getProjectKnowledge.mockResolvedValue([older, newer]);

    const { status, body } = await get("/api/projects/p1/notes");

    expect(status).toBe(200);
    // The freshest note wins — catches a reversed / removed createdAt sort.
    expect(body.note.id).toBe("n-new");
    expect(body.note.content).toBe("new brief");
    expect(fakeProjects.getProjectKnowledge).toHaveBeenCalledWith("p1", "notes_synthesis");
  });

  it("cross-user access → 404 (NOT 403, never leak existence)", async () => {
    // Project exists but is owned by someone else.
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "other-99", name: "P" });
    currentUser = { id: "owner-1" };

    const { status, body } = await get("/api/projects/p1/notes");

    expect(status).toBe(404); // an inverted `===`/`!==` ownership check would leak → 200
    expect(status).not.toBe(403);
    expect(body.error).toMatch(/not found/i);
    // Never even read the notes rows for a non-owner.
    expect(fakeProjects.getProjectKnowledge).not.toHaveBeenCalled();
  });

  it("owner but no synthesis rows yet → 404", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    fakeProjects.getProjectKnowledge.mockResolvedValue([]);

    const { status, body } = await get("/api/projects/p1/notes");

    expect(status).toBe(404);
    expect(body.error).toMatch(/no synthesis/i);
  });

  it("unauthenticated → 401", async () => {
    currentUser = null; // no req.user attached
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });

    const { status } = await get("/api/projects/p1/notes");

    expect(status).toBe(401);
    expect(fakeProjects.getProject).not.toHaveBeenCalled();
  });

  it("unexpected repo throw → 500 (internal bug, not an upstream 502)", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "owner-1", name: "P" });
    fakeProjects.getProjectKnowledge.mockRejectedValue(new Error("db exploded"));

    const { status, body } = await get("/api/projects/p1/notes");

    expect(status).toBe(500);
    expect(body.error).toMatch(/failed to fetch/i);
  });
});

describe("notes-routes — POST /api/projects/:id/notes/refresh", () => {
  beforeEach(() => {
    // Default happy-path context for the refresh handler.
    fakeProjects.getProject.mockResolvedValue({
      id: "p1",
      userId: "owner-1",
      name: "My project",
      description: "desc",
    });
    fakeProjects.loadProjectContext.mockResolvedValue({
      recentWorkflows: [],
      recentEpisodes: [],
    });
  });

  it("owner → 201 with the created note", async () => {
    callGeminiFlash.mockResolvedValue("# Synthesis\n\nreal markdown");
    const savedRow = { id: "note-created", content: "# Synthesis\n\nreal markdown" };
    fakeProjects.addProjectKnowledge.mockResolvedValue(savedRow);

    const { status, body } = await post("/api/projects/p1/notes/refresh");

    expect(status).toBe(201);
    expect(body.note).toEqual(savedRow);
    // The row it persists must be typed as notes_synthesis with the LLM
    // markdown as content — catches a wrong knowledgeType / dropped body.
    const arg = fakeProjects.addProjectKnowledge.mock.calls[0][0];
    expect(arg.knowledgeType).toBe("notes_synthesis");
    expect(arg.content).toBe("# Synthesis\n\nreal markdown");
    expect(arg.projectId).toBe("p1");
  });

  it("cross-user → 404 and never calls the LLM or persists a row", async () => {
    fakeProjects.getProject.mockResolvedValue({ id: "p1", userId: "other-99", name: "P" });

    const { status } = await post("/api/projects/p1/notes/refresh");

    expect(status).toBe(404);
    expect(callGeminiFlash).not.toHaveBeenCalled();
    expect(fakeProjects.addProjectKnowledge).not.toHaveBeenCalled();
  });

  it("LLM call rejects → 502 (upstream failure, not 500) and no row persisted", async () => {
    callGeminiFlash.mockRejectedValue(new Error("gemini 503"));

    const { status, body } = await post("/api/projects/p1/notes/refresh");

    expect(status).toBe(502);
    expect(body.error).toMatch(/synthesis failed/i);
    expect(fakeProjects.addProjectKnowledge).not.toHaveBeenCalled();
  });

  it("LLM returns empty/whitespace content → 502, no empty row persisted", async () => {
    callGeminiFlash.mockResolvedValue("   \n  ");

    const { status, body } = await post("/api/projects/p1/notes/refresh");

    expect(status).toBe(502);
    expect(body.error).toMatch(/empty/i);
    expect(fakeProjects.addProjectKnowledge).not.toHaveBeenCalled();
  });

  it("unexpected throw before the LLM → 500", async () => {
    // loadProjectContext explodes → generic internal error, not 502.
    callGeminiFlash.mockResolvedValue("# ok");
    fakeProjects.loadProjectContext.mockRejectedValue(new Error("ctx boom"));

    const { status, body } = await post("/api/projects/p1/notes/refresh");

    expect(status).toBe(500);
    expect(body.error).toMatch(/failed to refresh/i);
    expect(callGeminiFlash).not.toHaveBeenCalled();
  });

  it("unauthenticated → 401", async () => {
    currentUser = null;

    const { status } = await post("/api/projects/p1/notes/refresh");

    expect(status).toBe(401);
    expect(fakeProjects.getProject).not.toHaveBeenCalled();
  });
});
