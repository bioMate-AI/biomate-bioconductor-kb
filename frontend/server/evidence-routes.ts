/**
 * Evidence Search routes — cross-cutting layer.
 *
 * Lets any authenticated user submit a claim / finding / hypothesis,
 * parses the salient entities (genes / pathways / compounds / traits)
 * with an LLM if not provided, queries registered evidence datasets
 * in parallel (PubMed E-utilities, OpenTargets Platform v24 GraphQL,
 * STRING v12 PPI for v1), then LLM-reranks the gathered evidence with
 * inline citations and relevance scores.
 *
 * Sources are read from `backend/reference_data_complete.json`
 * (cached for 5 minutes) — any entry with integration_mode of "api"
 * or "api_and_download" is considered an active evidence source.
 *
 * Caching: in-process Map with TTL (1 hour) keyed by sha256 of the
 * (claim, context) pair. Politeness + cost control — PubMed asks for
 * <= 3 req/s without an API key, and LLM rerank costs real money.
 *
 * Cost cap: maxTokens=2048 for the rerank call, PubMed<=10 results,
 * OpenTargets<=5 results, STRING<=5 results.
 *
 * Auth: every endpoint requires authenticateToken. Evidence search has
 * no project scope for v1 — any logged-in user can search.
 *
 * Endpoints:
 *   POST /api/evidence/search   → run a search
 *   GET  /api/evidence/sources  → list active evidence datasets
 */

import type { Express, Request, Response } from "express";
import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { authenticateToken } from "./auth-middleware";
import { callGeminiFlash } from "./gemini-flash";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─── Constants (cost / politeness caps) ───────────────────────────────
const LLM_MAX_TOKENS = 2048;
const MAX_PUBMED_RESULTS = 10;
const MAX_OPENTARGETS_RESULTS = 5;
const MAX_STRING_RESULTS = 5;
const EVIDENCE_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour
const SOURCES_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

// Resolve the dataset catalog (lives in backend/, but consumed here).
const REFERENCE_DATA_PATH = path.resolve(
  __dirname,
  "..",
  "..",
  "backend",
  "reference_data_complete.json",
);

// ─── Types ─────────────────────────────────────────────────────────────
interface ParsedEntities {
  genes?: string[];
  pathways?: string[];
  compounds?: string[];
  traits?: string[];
}

interface EvidenceItem {
  source: string;
  source_url: string;
  title: string;
  snippet: string;
  doi?: string;
  relevance_score: number;
  confidence: number;
}

interface CachedSearch {
  expiresAt: number;
  payload: any;
}

// In-process caches. Module-level so they survive across requests but
// not across restarts (which is exactly what we want for v1 — no Redis,
// no Postgres row, no eviction policy beyond TTL).
export const _evidenceCache = new Map<string, CachedSearch>();
let _sourcesCache: { expiresAt: number; sources: any[] } | null = null;

function userId(req: Request): string | null {
  const u = (req as any).user;
  return u?.id ? String(u.id) : null;
}

function cacheKey(claim: string, context: ParsedEntities | undefined): string {
  const h = crypto.createHash("sha256");
  h.update(claim.trim().toLowerCase());
  h.update("|");
  h.update(JSON.stringify(context ?? {}));
  return h.digest("hex");
}

/**
 * Load the dataset catalog and project the API-mode entries down to
 * the shape we return from GET /api/evidence/sources. Cached for 5
 * minutes — the file is ~2 MB and rarely changes at runtime.
 */
function loadEvidenceSources(): any[] {
  const now = Date.now();
  if (_sourcesCache && _sourcesCache.expiresAt > now) {
    return _sourcesCache.sources;
  }

  const sources: any[] = [];
  try {
    const raw = fs.readFileSync(REFERENCE_DATA_PATH, "utf-8");
    const catalog = JSON.parse(raw) as Record<string, any>;
    // Catalog is grouped by category at the top level. Walk every
    // group, pick entries whose integration_mode is api / api_and_download.
    for (const groupKey of Object.keys(catalog)) {
      const group = catalog[groupKey];
      if (!group || typeof group !== "object") continue;
      for (const datasetKey of Object.keys(group)) {
        const ds = group[datasetKey];
        if (!ds || typeof ds !== "object") continue;
        const mode = ds.integration_mode;
        if (mode !== "api" && mode !== "api_and_download") continue;
        sources.push({
          id: datasetKey,
          name: ds.name ?? datasetKey,
          display_name: ds.display_name ?? ds.name ?? datasetKey,
          source_url: ds.source_url ?? null,
          integration_mode: mode,
          category: ds.category ?? groupKey,
          license: ds.license ?? null,
        });
      }
    }
  } catch (e: any) {
    console.error("[evidence] failed to load reference catalog:", e?.message ?? e);
  }

  _sourcesCache = { expiresAt: now + SOURCES_CACHE_TTL_MS, sources };
  return sources;
}

// ─── Entity parsing (LLM) ──────────────────────────────────────────────
async function parseClaimEntities(claim: string): Promise<ParsedEntities> {
  const system =
    "You extract biomedical entities from a single claim or hypothesis. " +
    "Reply with ONLY a JSON object with optional keys: genes (HGNC symbols), " +
    "pathways (Reactome / KEGG names), compounds (drug / chemical names), " +
    "traits (disease / phenotype names). Use [] for empty lists. No prose.";
  try {
    const raw = await callGeminiFlash({
      system,
      messages: [{ role: "user", content: claim }],
      maxTokens: 512,
      temperature: 0,
      jsonMode: true,
    });
    const parsed = JSON.parse(raw);
    return {
      genes: Array.isArray(parsed.genes) ? parsed.genes : [],
      pathways: Array.isArray(parsed.pathways) ? parsed.pathways : [],
      compounds: Array.isArray(parsed.compounds) ? parsed.compounds : [],
      traits: Array.isArray(parsed.traits) ? parsed.traits : [],
    };
  } catch (e: any) {
    console.error("[evidence] claim parse failed:", e?.message ?? e);
    return {};
  }
}

// ─── PubMed E-utilities ────────────────────────────────────────────────
export async function queryPubMed(
  claim: string,
  entities: ParsedEntities,
  fetchImpl: typeof fetch = fetch,
): Promise<EvidenceItem[]> {
  const terms = [
    ...(entities.genes ?? []),
    ...(entities.traits ?? []),
    ...(entities.compounds ?? []),
  ].filter(Boolean);
  const query = terms.length > 0 ? terms.join(" AND ") : claim;
  const base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils";
  const esearch =
    `${base}/esearch.fcgi?db=pubmed&retmode=json&retmax=${MAX_PUBMED_RESULTS}` +
    `&term=${encodeURIComponent(query)}`;
  const r1 = await fetchImpl(esearch);
  if (!r1.ok) throw new Error(`PubMed esearch ${r1.status}`);
  const j1: any = await r1.json();
  const ids: string[] = (j1?.esearchresult?.idlist ?? []).slice(
    0,
    MAX_PUBMED_RESULTS,
  );
  if (ids.length === 0) return [];

  const esummary =
    `${base}/esummary.fcgi?db=pubmed&retmode=json&id=${ids.join(",")}`;
  const r2 = await fetchImpl(esummary);
  if (!r2.ok) throw new Error(`PubMed esummary ${r2.status}`);
  const j2: any = await r2.json();
  const result = j2?.result ?? {};

  return ids
    .map((id) => {
      const rec = result[id];
      if (!rec) return null;
      const doi: string | undefined = (rec.articleids ?? []).find(
        (a: any) => a.idtype === "doi",
      )?.value;
      return {
        source: "pubmed_eutils",
        source_url: `https://pubmed.ncbi.nlm.nih.gov/${id}/`,
        title: rec.title ?? `PMID ${id}`,
        snippet: [rec.source, rec.pubdate, (rec.authors ?? [])
          .slice(0, 3)
          .map((a: any) => a.name)
          .join(", ")]
          .filter(Boolean)
          .join(" — "),
        doi,
        relevance_score: 0,
        confidence: 0.5,
      } as EvidenceItem;
    })
    .filter((x): x is EvidenceItem => x !== null);
}

// ─── OpenTargets Platform v24 (GraphQL) ────────────────────────────────
export async function queryOpenTargets(
  entities: ParsedEntities,
  fetchImpl: typeof fetch = fetch,
): Promise<EvidenceItem[]> {
  const gene = (entities.genes ?? [])[0];
  if (!gene) return [];

  const query = `query EvidenceSearch($q: String!) {
    search(queryString: $q, entityNames: ["target"]) {
      hits { id name entity description }
    }
  }`;
  const r = await fetchImpl("https://api.platform.opentargets.org/api/v4/graphql", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables: { q: gene } }),
  });
  if (!r.ok) throw new Error(`OpenTargets ${r.status}`);
  const j: any = await r.json();
  const hits: any[] = (j?.data?.search?.hits ?? []).slice(0, MAX_OPENTARGETS_RESULTS);
  return hits.map((h) => ({
    source: "opentargets_platform_v24",
    source_url: `https://platform.opentargets.org/target/${h.id}`,
    title: `${h.name ?? h.id} (target)`,
    snippet: h.description ?? `OpenTargets entity ${h.entity ?? "target"} for ${h.name ?? h.id}.`,
    relevance_score: 0,
    confidence: 0.6,
  }));
}

// ─── STRING v12 (REST) ─────────────────────────────────────────────────
export async function queryStringDb(
  entities: ParsedEntities,
  fetchImpl: typeof fetch = fetch,
): Promise<EvidenceItem[]> {
  const genes = (entities.genes ?? []).slice(0, MAX_STRING_RESULTS);
  if (genes.length === 0) return [];
  const url =
    "https://string-db.org/api/json/network?identifiers=" +
    encodeURIComponent(genes.join("%0d")) +
    "&limit=" + MAX_STRING_RESULTS;
  const r = await fetchImpl(url);
  if (!r.ok) throw new Error(`STRING ${r.status}`);
  const arr: any[] = await r.json();
  return arr.slice(0, MAX_STRING_RESULTS).map((e: any) => ({
    source: "string_db_v12",
    source_url: `https://string-db.org/cgi/network?identifiers=${encodeURIComponent(
      e.preferredName_A ?? "",
    )}%0d${encodeURIComponent(e.preferredName_B ?? "")}`,
    title: `${e.preferredName_A} ↔ ${e.preferredName_B} (PPI)`,
    snippet:
      `STRING combined_score=${e.score ?? "?"} between ${e.preferredName_A} and ` +
      `${e.preferredName_B}.`,
    relevance_score: 0,
    confidence: typeof e.score === "number" ? Math.min(1, e.score) : 0.5,
  }));
}

// TODO(v2): wire ClinVar, GTEx, Reactome, KEGG, MSigDB into the same
// parallel dispatcher. The shape returned by each adapter is the same
// EvidenceItem above, so the rerank step is source-agnostic.

// ─── LLM rerank ────────────────────────────────────────────────────────
async function rerankEvidence(
  claim: string,
  items: EvidenceItem[],
): Promise<EvidenceItem[]> {
  if (items.length === 0) return [];
  const system =
    "You score each piece of evidence for how strongly it supports or refutes " +
    "the user's claim. Reply with ONLY a JSON array of " +
    "{ index:number, relevance_score:number 0..1, confidence:number 0..1, summary:string } " +
    "objects, one per input item, in the same order. No prose.";
  const numbered = items
    .map((it, i) =>
      `[${i}] (${it.source}) ${it.title}\n    ${it.snippet}`,
    )
    .join("\n");
  const user = `Claim: ${claim}\n\nEvidence items:\n${numbered}`;

  const raw = await callGeminiFlash({
    system,
    messages: [{ role: "user", content: user }],
    maxTokens: LLM_MAX_TOKENS,
    temperature: 0,
    jsonMode: true,
  });
  const scored = JSON.parse(raw);
  if (!Array.isArray(scored)) return items;
  const merged = items.map((it, i) => {
    const s = scored.find((x: any) => x?.index === i) ?? scored[i] ?? {};
    return {
      ...it,
      relevance_score:
        typeof s.relevance_score === "number" ? s.relevance_score : it.relevance_score,
      confidence:
        typeof s.confidence === "number" ? s.confidence : it.confidence,
      snippet: typeof s.summary === "string" && s.summary.length > 0 ? s.summary : it.snippet,
    };
  });
  merged.sort((a, b) => b.relevance_score - a.relevance_score);
  return merged;
}

export function registerEvidenceRoutes(app: Express): void {
  // ─── POST /api/evidence/search ───────────────────────────────────────
  app.post(
    "/api/evidence/search",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });

      const claim: string | undefined = req.body?.claim;
      if (!claim || typeof claim !== "string" || claim.trim().length === 0) {
        return res.status(400).json({ error: "Missing required field: claim" });
      }
      const providedContext: ParsedEntities | undefined = req.body?.context;

      // Cache hit short-circuits all external calls + LLM.
      const key = cacheKey(claim, providedContext);
      const cached = _evidenceCache.get(key);
      if (cached && cached.expiresAt > Date.now()) {
        return res.json({ ...cached.payload, cached: true });
      }

      // Step a: entity parsing (skip if user supplied context).
      const entities: ParsedEntities = providedContext
        ? providedContext
        : await parseClaimEntities(claim);

      // Step b: parallel dataset queries. One failure must NOT poison
      // the others — use Promise.allSettled and ignore rejections.
      const settled = await Promise.allSettled([
        queryPubMed(claim, entities),
        queryOpenTargets(entities),
        queryStringDb(entities),
      ]);
      const evidence: EvidenceItem[] = [];
      const sourceErrors: Record<string, string> = {};
      const sourceNames = ["pubmed_eutils", "opentargets_platform_v24", "string_db_v12"];
      for (let i = 0; i < settled.length; i++) {
        const r = settled[i];
        if (r.status === "fulfilled") {
          evidence.push(...r.value);
        } else {
          sourceErrors[sourceNames[i]] = String(r.reason?.message ?? r.reason);
        }
      }

      // Step c: LLM rerank. If the LLM fails, surface as 502.
      let ranked: EvidenceItem[];
      try {
        ranked = await rerankEvidence(claim, evidence);
      } catch (e: any) {
        console.error("[evidence] rerank failed:", e?.message ?? e);
        return res.status(502).json({ error: "LLM rerank failed" });
      }

      const payload = {
        claim,
        parsed_entities: entities,
        evidence: ranked,
        source_errors: sourceErrors,
      };
      _evidenceCache.set(key, {
        expiresAt: Date.now() + EVIDENCE_CACHE_TTL_MS,
        payload,
      });
      return res.json(payload);
    },
  );

  // ─── GET /api/evidence/sources ───────────────────────────────────────
  app.get(
    "/api/evidence/sources",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const sources = loadEvidenceSources();
      return res.json({ sources });
    },
  );
}
