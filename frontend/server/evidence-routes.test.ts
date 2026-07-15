/**
 * Evidence Search source-level contract tests.
 *
 * Same shape as notes-routes.test.ts —
 * lock in the policy invariants (auth, validation, caching, cost
 * caps, failure containment) without booting Postgres or making
 * real HTTP calls. The dispatcher functions (queryPubMed,
 * queryOpenTargets, queryStringDb) are also exercised directly with
 * an injected fetch mock so cap enforcement + URL shape are real.
 */
import { describe, expect, it, vi, beforeEach } from "vitest";
import * as fs from "fs";
import * as path from "path";
import {
  queryPubMed,
  queryOpenTargets,
  queryStringDb,
  _evidenceCache,
} from "./evidence-routes";

const SRC = fs.readFileSync(path.join(__dirname, "evidence-routes.ts"), "utf-8");

describe("evidence-routes — contract (source)", () => {
  it("registers both endpoints", () => {
    expect(SRC.match(/app\.post\(\s*"\/api\/evidence\/search"/)?.length).toBe(1);
    expect(SRC.match(/app\.get\(\s*"\/api\/evidence\/sources"/)?.length).toBe(1);
  });

  it("both endpoints go through authenticateToken", () => {
    const handlers =
      SRC.match(
        /app\.(get|post)\(\s*"\/api\/evidence\/[^"]*",\s*\n?\s*authenticateToken/g,
      ) ?? [];
    expect(handlers.length).toBe(2);
  });

  it("unauthenticated request short-circuits with 401", () => {
    const matches = SRC.match(/if\s*\(!uid\)\s*return\s+res\.status\(401\)/g) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(2);
  });

  it("missing claim returns 400", () => {
    expect(/Missing required field: claim/.test(SRC)).toBe(true);
    expect(/res\.status\(400\)/.test(SRC)).toBe(true);
  });

  it("response shape includes claim + parsed_entities + evidence", () => {
    expect(/claim,\s*\n\s*parsed_entities/.test(SRC)).toBe(true);
    expect(/evidence:\s*ranked/.test(SRC)).toBe(true);
  });

  it("uses Promise.allSettled so one source failure does not poison the others", () => {
    expect(/Promise\.allSettled/.test(SRC)).toBe(true);
    expect(/sourceErrors/.test(SRC)).toBe(true);
  });

  it("LLM rerank failure surfaces as 502, not 500", () => {
    expect(/LLM rerank failed/.test(SRC)).toBe(true);
    expect(/return\s+res\.status\(502\)/.test(SRC)).toBe(true);
  });

  it("uses callGeminiFlash with bounded maxTokens=2048 for the rerank", () => {
    expect(SRC.includes("callGeminiFlash")).toBe(true);
    expect(/LLM_MAX_TOKENS\s*=\s*2048/.test(SRC)).toBe(true);
    expect(/maxTokens:\s*LLM_MAX_TOKENS/.test(SRC)).toBe(true);
  });

  it("hard cap constants are present (10 / 5 / 5)", () => {
    expect(/MAX_PUBMED_RESULTS\s*=\s*10/.test(SRC)).toBe(true);
    expect(/MAX_OPENTARGETS_RESULTS\s*=\s*5/.test(SRC)).toBe(true);
    expect(/MAX_STRING_RESULTS\s*=\s*5/.test(SRC)).toBe(true);
  });

  it("caches search results in _evidenceCache with 1-hour TTL", () => {
    expect(/_evidenceCache\s*=\s*new Map/.test(SRC)).toBe(true);
    expect(/EVIDENCE_CACHE_TTL_MS\s*=\s*60\s*\*\s*60\s*\*\s*1000/.test(SRC)).toBe(true);
  });

  it("sources endpoint caches for 5 minutes", () => {
    expect(/SOURCES_CACHE_TTL_MS\s*=\s*5\s*\*\s*60\s*\*\s*1000/.test(SRC)).toBe(true);
  });

  it("sources are derived from reference_data_complete.json (api / api_and_download)", () => {
    expect(/reference_data_complete\.json/.test(SRC)).toBe(true);
    expect(/integration_mode/.test(SRC)).toBe(true);
    expect(/api_and_download/.test(SRC)).toBe(true);
  });
});

describe("evidence-routes — registered into main router", () => {
  const ROUTES = fs.readFileSync(path.join(__dirname, "routes.ts"), "utf-8");
  it("the main router imports + calls registerEvidenceRoutes", () => {
    expect(
      /registerEvidenceRoutes\s*\}\s*=\s*await\s+import\("\.\/evidence-routes"\)/.test(
        ROUTES,
      ),
    ).toBe(true);
    expect(/registerEvidenceRoutes\(app\)/.test(ROUTES)).toBe(true);
  });
});

// ─── Adapter behaviour with injected fetch (real cap + URL shape) ────
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
