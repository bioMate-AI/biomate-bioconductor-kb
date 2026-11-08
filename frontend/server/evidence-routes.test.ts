/**
 * Evidence Search route tests.
 *
 * Two halves:
 *   1. ROUTE BEHAVIOUR (new) — mounts the real `registerEvidenceRoutes`
 *      handler on an express app and drives it over loopback HTTP with
 *      the auth + LLM seams faked and global fetch stubbed for the
 *      dataset adapters. Asserts STATUS + BODY: 400 on missing claim,
 *      502 when the rerank LLM throws, 200 with a populated
 *      `source_errors` map when one adapter rejects (Promise.allSettled
 *      containment), and a `cached:true` short-circuit on cache hit.
 *      (Replaces the old 100%-source-grep "contract (source)" block that
 *      also grepped dead-code 401 branches — see
 *      docs/20260909_UPGRADE_TEST_QUALITY_AUDIT.md gap #3.)
 *   2. ADAPTER BEHAVIOUR (unchanged) — exercises queryPubMed /
 *      queryOpenTargets / queryStringDb directly with an injected fetch.
 *
 * Note: the route handler calls the REAL adapter functions with the
 * global fetch, so we mock the ./auth-middleware and ./gemini-flash
 * modules (separate files — the adapters live in evidence-routes.ts and
 * must stay real) and stub globalThis.fetch per test.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express, { type Express } from "express";
import type { Server } from "http";

// Real fetch, captured before any stubbing — used to call our own
// test server. The adapters use globalThis.fetch, which we stub below.
const httpFetch = globalThis.fetch;

const callGeminiFlash = vi.fn();

vi.mock("./auth-middleware", () => ({
  authenticateToken: (_req: any, _res: any, next: any) => next(),
}));
vi.mock("./gemini-flash", () => ({
  callGeminiFlash: (...args: any[]) => callGeminiFlash(...args),
}));

// Imported after the mocks are declared (vi.mock is hoisted anyway).
import {
  queryPubMed,
  queryOpenTargets,
  queryStringDb,
  _evidenceCache,
} from "./evidence-routes";

let app: Express;
let server: Server;
let baseUrl = "";
let currentUser: { id: string } | null = null;

beforeAll(async () => {
  const { registerEvidenceRoutes } = await import("./evidence-routes");
  app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    if (currentUser) (req as any).user = currentUser;
    next();
  });
  registerEvidenceRoutes(app);
  await new Promise<void>((r) => {
    server = app.listen(0, "127.0.0.1", () => r());
  });
  const { port } = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${port}`;
});

afterAll(() => {
  server?.close();
});

async function postSearch(payload: unknown) {
  const r = await httpFetch(`${baseUrl}/api/evidence/search`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const body = await r.json().catch(() => ({}));
  return { status: r.status, body };
}

// A stub `fetch` for the adapters. Each adapter makes 1-2 calls; we key
// deterministic behaviour off the URL so we can make ONE source fail
// while the others succeed.
function stubAdapterFetch(opts: {
  pubmed?: "ok" | "fail";
  opentargets?: "ok" | "fail";
  string?: "ok" | "fail";
} = {}) {
  vi.stubGlobal("fetch", (async (url: any) => {
    const u = String(url);
    const jsonRes = (json: any, ok = true, status = 200) =>
      ({ ok, status, json: async () => json }) as any;

    if (u.includes("eutils.ncbi.nlm.nih.gov")) {
      if (opts.pubmed === "fail") return jsonRes({}, false, 503);
      if (u.includes("esearch")) {
        return jsonRes({ esearchresult: { idlist: ["111"] } });
      }
      return jsonRes({
        result: { "111": { title: "PubMed hit", articleids: [] } },
      });
    }
    if (u.includes("api.platform.opentargets.org")) {
      if (opts.opentargets === "fail") return jsonRes({}, false, 500);
      return jsonRes({ data: { search: { hits: [{ id: "ENSG1", name: "TP53" }] } } });
    }
    if (u.includes("string-db.org")) {
      if (opts.string === "fail") return jsonRes({}, false, 502);
      return jsonRes([{ preferredName_A: "TP53", preferredName_B: "MDM2", score: 0.9 }]);
    }
    return jsonRes({}, false, 404);
  }) as any);
}

describe("evidence-routes — POST /api/evidence/search (behaviour)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.unstubAllGlobals();
    _evidenceCache.clear();
    currentUser = { id: "u-1" };
  });

  afterAll(() => {
    vi.unstubAllGlobals();
  });

  it("missing claim → 400", async () => {
    const { status, body } = await postSearch({ context: { genes: ["TP53"] } });
    expect(status).toBe(400);
    expect(body.error).toMatch(/claim/i);
  });

  it("blank/whitespace claim → 400", async () => {
    const { status } = await postSearch({ claim: "   " });
    expect(status).toBe(400);
  });

  it("rerank LLM throws → 502 (upstream failure, not 500)", async () => {
    stubAdapterFetch({}); // all sources ok → we get evidence to rerank
    callGeminiFlash.mockRejectedValue(new Error("gemini 500"));

    // Supply context so parseClaimEntities (also an LLM call) is skipped;
    // the ONLY LLM call left is the rerank, so its failure is isolated.
    const { status, body } = await postSearch({
      claim: "TP53 drives tumour growth",
      context: { genes: ["TP53"] },
    });

    expect(status).toBe(502);
    expect(body.error).toMatch(/rerank/i);
  });

  it("one adapter rejects → 200 with source_errors populated (allSettled containment)", async () => {
    // OpenTargets fails; PubMed + STRING succeed. The request must still
    // succeed with the surviving evidence, recording the failure.
    stubAdapterFetch({ opentargets: "fail" });
    callGeminiFlash.mockResolvedValue(JSON.stringify([])); // rerank returns [] → keeps input order

    const { status, body } = await postSearch({
      claim: "TP53 and MDM2 interact",
      context: { genes: ["TP53"] },
    });

    expect(status).toBe(200);
    expect(body.source_errors).toBeTruthy();
    // The failing source is recorded; the healthy ones are not.
    expect(body.source_errors.opentargets_platform_v24).toBeTruthy();
    expect(body.source_errors.pubmed_eutils).toBeUndefined();
    expect(body.source_errors.string_db_v12).toBeUndefined();
    // Surviving evidence still came through (containment worked).
    expect(Array.isArray(body.evidence)).toBe(true);
    expect(body.evidence.length).toBeGreaterThan(0);
  });

  it("cache hit → short-circuits with cached:true and skips the LLM", async () => {
    stubAdapterFetch({});
    callGeminiFlash.mockResolvedValue(JSON.stringify([]));

    const payload = { claim: "cached claim", context: { genes: ["TP53"] } };

    const first = await postSearch(payload);
    expect(first.status).toBe(200);
    expect(first.body.cached).toBeUndefined(); // fresh: no cached flag

    const llmCallsAfterFirst = callGeminiFlash.mock.calls.length;

    // Identical request → served from _evidenceCache, no new LLM call.
    const second = await postSearch(payload);
    expect(second.status).toBe(200);
    expect(second.body.cached).toBe(true);
    expect(callGeminiFlash.mock.calls.length).toBe(llmCallsAfterFirst);
  });

  it("unauthenticated → 401", async () => {
    currentUser = null;
    const { status } = await postSearch({ claim: "x", context: { genes: ["TP53"] } });
    expect(status).toBe(401);
  });
});

// ─── Adapter behaviour with injected fetch (real cap + URL shape) ────
// UNCHANGED from the original suite — this half was already good.
function makeFetch(responses: Array<{ ok?: boolean; status?: number; json: any }>): typeof fetch {
  let i = 0;
  return (async (_url: any, _init?: any) => {
    const r = responses[i++] ?? responses[responses.length - 1];
    return {
      ok: r.ok ?? true,
      status: r.status ?? 200,
      json: async () => r.json,
    } as any;
  }) as any;
}

describe("evidence-routes — adapter behaviour", () => {
  beforeEach(() => {
    _evidenceCache.clear();
  });

  it("PubMed adapter caps results at MAX_PUBMED_RESULTS (10)", async () => {
    const manyIds = Array.from({ length: 25 }, (_, i) => String(1000 + i));
    const summary: any = { result: {} };
    for (const id of manyIds.slice(0, 10)) {
      summary.result[id] = {
        title: `Paper ${id}`,
        source: "J Test",
        pubdate: "2026",
        authors: [{ name: "Doe J" }],
        articleids: [{ idtype: "doi", value: `10.0/${id}` }],
      };
    }
    const fakeFetch = makeFetch([
      { json: { esearchresult: { idlist: manyIds } } },
      { json: summary },
    ]);
    const out = await queryPubMed("test claim", { genes: ["TP53"] }, fakeFetch);
    expect(out.length).toBeLessThanOrEqual(10);
    expect(out[0].source).toBe("pubmed_eutils");
    expect(out[0].source_url).toMatch(/^https:\/\/pubmed\.ncbi\.nlm\.nih\.gov\//);
    expect(out[0].doi).toMatch(/^10\./);
  });

  it("PubMed returns [] when no IDs match", async () => {
    const fakeFetch = makeFetch([{ json: { esearchresult: { idlist: [] } } }]);
    const out = await queryPubMed("nothing", {}, fakeFetch);
    expect(out).toEqual([]);
  });

  it("OpenTargets adapter caps hits at MAX_OPENTARGETS_RESULTS (5)", async () => {
    const hits = Array.from({ length: 12 }, (_, i) => ({
      id: `ENSG${i}`,
      name: `GENE${i}`,
      entity: "target",
      description: `desc ${i}`,
    }));
    const fakeFetch = makeFetch([{ json: { data: { search: { hits } } } }]);
    const out = await queryOpenTargets({ genes: ["TP53"] }, fakeFetch);
    expect(out.length).toBe(5);
    expect(out[0].source).toBe("opentargets_platform_v24");
  });

  it("OpenTargets adapter returns [] when no gene is parsed", async () => {
    const fakeFetch = makeFetch([{ json: {} }]);
    const out = await queryOpenTargets({}, fakeFetch);
    expect(out).toEqual([]);
  });

  it("STRING adapter caps edges at MAX_STRING_RESULTS (5)", async () => {
    const edges = Array.from({ length: 20 }, (_, i) => ({
      preferredName_A: `A${i}`,
      preferredName_B: `B${i}`,
      score: 0.9,
    }));
    const fakeFetch = makeFetch([{ json: edges }]);
    const out = await queryStringDb({ genes: ["TP53", "EGFR"] }, fakeFetch);
    expect(out.length).toBe(5);
    expect(out[0].source).toBe("string_db_v12");
  });

  it("STRING adapter returns [] when no genes are parsed", async () => {
    const fakeFetch = makeFetch([{ json: [] }]);
    const out = await queryStringDb({}, fakeFetch);
    expect(out).toEqual([]);
  });

  it("adapter throws on non-ok HTTP (so dispatcher can record it without breaking siblings)", async () => {
    const fakeFetch = makeFetch([{ ok: false, status: 503, json: {} }]);
    await expect(queryPubMed("x", { genes: ["X"] }, fakeFetch)).rejects.toThrow(/PubMed/);
  });
});
