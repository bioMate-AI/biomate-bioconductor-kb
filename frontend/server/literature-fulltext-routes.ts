/**
 * Literature reader — open-access text for a cited source.
 *
 * The chat's citation "Read" action used to open a pane that showed whatever
 * abstract happened to travel on the citation (usually none) followed by
 * "Full text is not available". No full-text fetch existed (review
 * docs/20261110_EPAR_DATASET_CHAT_UX_REVIEW.md §3 C3).
 *
 * This route resolves a source by PMCID / PMID / DOI against Europe PMC and
 * returns, honestly:
 *   - the record's metadata + abstract (when Europe PMC has one);
 *   - the open-access full text (JATS → sections/paragraphs) when the article
 *     is in the Europe PMC OA subset;
 *   - otherwise `fullTextStatus: "not_open_access"` with publisher / Europe PMC
 *     links — never a fabricated body.
 *
 * Endpoint (authenticated):
 *   GET /api/literature/fulltext?pmcid=PMC123&pmid=456&doi=10.x/y
 *
 * Europe PMC REST docs: https://europepmc.org/RestfulWebService
 */
import type { Express, RequestHandler } from "express";

const EPMC_BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest";
const FETCH_TIMEOUT_MS = 12_000;
const CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const CACHE_MAX = 200;
/** Upper bound on returned full text — a long review is ~150k chars. */
const MAX_FULLTEXT_CHARS = 250_000;

export interface FulltextSection {
  heading: string | null;
  paragraphs: string[];
}

export type FulltextStatus = "available" | "not_open_access" | "unavailable" | "not_found";

export interface FulltextResponse {
  found: boolean;
  source: "europepmc";
  ids: { pmid: string | null; pmcid: string | null; doi: string | null };
  title: string | null;
  journal: string | null;
  year: string | null;
  authors: string | null;
  abstract: string | null;
  openAccess: boolean;
  license: string | null;
  fullTextStatus: FulltextStatus;
  sections: FulltextSection[];
  truncated: boolean;
  links: { publisher: string | null; pubmed: string | null; pmc: string | null; europepmc: string | null };
}

export interface SourceIds {
  pmid?: string;
  pmcid?: string;
  doi?: string;
}

// ─── Input validation ────────────────────────────────────────────────────

export function normaliseIds(q: Record<string, unknown>): SourceIds | null {
  const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
  const pmid = str(q.pmid);
  const pmcidRaw = str(q.pmcid).toUpperCase();
  const doi = str(q.doi).replace(/^(?:https?:\/\/(?:dx\.)?doi\.org\/|doi:\s*)/i, "");
  const out: SourceIds = {};
  if (pmid && /^\d{1,9}$/.test(pmid)) out.pmid = pmid;
  if (pmcidRaw) {
    const pmcid = /^\d+$/.test(pmcidRaw) ? `PMC${pmcidRaw}` : pmcidRaw;
    if (/^PMC\d{1,10}$/.test(pmcid)) out.pmcid = pmcid;
  }
  // DOI syntax is permissive; we only refuse characters that would break the
  // quoted Europe PMC query (quotes, whitespace, control chars).
  if (doi && doi.length <= 200 && /^10\.\d{1,9}\/[^\s"\\]+$/.test(doi)) out.doi = doi;
  return out.pmid || out.pmcid || out.doi ? out : null;
}

export function buildSearchQuery(ids: SourceIds): string {
  if (ids.pmcid) return `PMCID:${ids.pmcid}`;
  if (ids.pmid) return `EXT_ID:${ids.pmid} AND SRC:MED`;
  return `DOI:"${ids.doi}"`;
}

// ─── JATS / HTML text helpers ───────────────────────────────────────────

const ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "–", mdash: "—",
  hellip: "…", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“", times: "×", plusmn: "±",
  minus: "−", le: "≤", ge: "≥", deg: "°", micro: "µ", alpha: "α", beta: "β", gamma: "γ",
};

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, body: string) => {
    if (body[0] === "#") {
      const code = body[1] === "x" || body[1] === "X" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[body.toLowerCase()] ?? m;
  });
}

/** Tag-strip + entity-decode + whitespace-collapse. */
export function toPlainText(markup: string): string {
  return decodeEntities(markup.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").replace(/\s+([,.;:)\]])/g, "$1").replace(/([(\[])\s+/g, "$1").trim();
}

/** Europe PMC abstracts carry light HTML (<h4>Background</h4>…). Keep section labels as text. */
export function abstractToText(html: string | null | undefined): string | null {
  if (!html) return null;
  const withBreaks = html.replace(/<\/?(h\d|p|br)\b[^>]*>/gi, "\n");
  const text = decodeEntities(withBreaks.replace(/<[^>]+>/g, ""))
    .split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter(Boolean).join("\n");
  return text || null;
}

/**
 * Extract readable sections from a JATS article. Deliberately small: section
 * titles become headings, <p> become paragraphs; figures, tables, formulas,
 * reference lists and supplementary blocks are dropped (they do not read as
 * prose). Returns at most MAX_FULLTEXT_CHARS of text.
 */
export function parseJatsBody(xml: string): { sections: FulltextSection[]; truncated: boolean } {
  const bodyMatch = xml.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
  if (!bodyMatch) return { sections: [], truncated: false };
  let body = bodyMatch[1];
  // Drop non-prose blocks entirely.
  for (const tag of ["fig", "table-wrap", "disp-formula", "supplementary-material", "ref-list", "fn-group", "graphic", "media"]) {
    body = body.replace(new RegExp(`<${tag}\\b[^>]*?(?:/>|>[\\s\\S]*?</${tag}>)`, "gi"), " ");
  }
  // Inline math: keep the alttext if present, otherwise drop MathML noise.
  body = body.replace(/<inline-formula\b[^>]*>([\s\S]*?)<\/inline-formula>/gi, (_m, inner: string) => {
    const alt = inner.match(/alttext="([^"]*)"/i)?.[1];
    return alt ? ` ${alt} ` : " ";
  });
  body = body.replace(/<mml:math\b[\s\S]*?<\/mml:math>/gi, " ");

  const sections: FulltextSection[] = [];
  let current: FulltextSection = { heading: null, paragraphs: [] };
  let total = 0;
  let truncated = false;
  const token = /<title\b[^>]*>([\s\S]*?)<\/title>|<p\b[^>]*>([\s\S]*?)<\/p>/gi;
  let m: RegExpExecArray | null;
  while ((m = token.exec(body))) {
    if (m[1] !== undefined) {
      const heading = toPlainText(m[1]);
      if (!heading) continue;
      if (current.heading !== null || current.paragraphs.length) sections.push(current);
      current = { heading, paragraphs: [] };
    } else {
      const text = toPlainText(m[2] ?? "");
      if (!text) continue;
      if (total + text.length > MAX_FULLTEXT_CHARS) { truncated = true; break; }
      total += text.length;
      current.paragraphs.push(text);
    }
  }
  if (current.heading !== null || current.paragraphs.length) sections.push(current);
  // A heading with no prose under it (e.g. a parent section whose text lives in
  // its children) still reads fine as a heading; only drop fully empty runs.
  return { sections: sections.filter((s) => s.heading || s.paragraphs.length), truncated };
}

// ─── Europe PMC client ──────────────────────────────────────────────────

type Fetch = typeof fetch;

async function fetchWithTimeout(fetcher: Fetch, url: string): Promise<Response> {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), FETCH_TIMEOUT_MS);
  try {
    return await fetcher(url, { signal: abort.signal, headers: { Accept: "application/json, application/xml" } });
  } finally {
    clearTimeout(timer);
  }
}

export class UpstreamError extends Error {}

export async function resolveFulltext(ids: SourceIds, fetcher: Fetch = fetch): Promise<FulltextResponse> {
  const searchUrl = `${EPMC_BASE}/search?query=${encodeURIComponent(buildSearchQuery(ids))}&resultType=core&format=json&pageSize=1`;
  const searchRes = await fetchWithTimeout(fetcher, searchUrl);
  if (!searchRes.ok) throw new UpstreamError(`Europe PMC search ${searchRes.status}`);
  const searchJson: any = await searchRes.json();
  const rec: any = searchJson?.resultList?.result?.[0];

  const doiLink = (doi: string | null) => (doi ? `https://doi.org/${doi}` : null);
  // Europe PMC *article pages* (europepmc.org/article/...) return 403 to automated
  // clients, so they can't be opened from a citation link. Surface NCBI PubMed / PMC
  // links (which resolve) as the primary "read" targets; keep Europe PMC only as a
  // last resort. (The Europe PMC REST API we query above is unaffected — it's the
  // human article page that is blocked.)
  const pubmedLink = (pmid: string | null) => (pmid ? `https://pubmed.ncbi.nlm.nih.gov/${pmid}/` : null);
  const pmcLink = (pmcid: string | null) =>
    (pmcid ? `https://www.ncbi.nlm.nih.gov/pmc/articles/${pmcid.startsWith("PMC") ? pmcid : "PMC" + pmcid}/` : null);
  if (!rec) {
    return {
      found: false, source: "europepmc",
      ids: { pmid: ids.pmid ?? null, pmcid: ids.pmcid ?? null, doi: ids.doi ?? null },
      title: null, journal: null, year: null, authors: null, abstract: null,
      openAccess: false, license: null, fullTextStatus: "not_found", sections: [], truncated: false,
      links: {
        publisher: doiLink(ids.doi ?? null),
        pubmed: pubmedLink(ids.pmid ?? null),
        pmc: pmcLink(ids.pmcid ?? null),
        europepmc: ids.pmid ? `https://europepmc.org/article/MED/${ids.pmid}` : null,
      },
    };
  }

  const pmid: string | null = rec.pmid ?? (rec.source === "MED" ? rec.id : null) ?? ids.pmid ?? null;
  const pmcid: string | null = rec.pmcid ?? ids.pmcid ?? null;
  const doi: string | null = rec.doi ?? ids.doi ?? null;
  const openAccess = rec.isOpenAccess === "Y";

  let sections: FulltextSection[] = [];
  let truncated = false;
  let fullTextStatus: FulltextStatus = openAccess ? "unavailable" : "not_open_access";
  if (openAccess && pmcid) {
    try {
      const ftRes = await fetchWithTimeout(fetcher, `${EPMC_BASE}/${pmcid}/fullTextXML`);
      if (ftRes.ok) {
        const parsed = parseJatsBody(await ftRes.text());
        sections = parsed.sections;
        truncated = parsed.truncated;
        if (sections.length) fullTextStatus = "available";
      } else {
        await ftRes.body?.cancel();
      }
    } catch {
      // Network failure on the full-text leg degrades to the abstract — the
      // status says "unavailable", not "not open access".
    }
  }

  return {
    found: true, source: "europepmc",
    ids: { pmid, pmcid, doi },
    title: rec.title ? toPlainText(String(rec.title)) : null,
    journal: rec.journalInfo?.journal?.title ?? rec.journalTitle ?? null,
    year: rec.pubYear ?? null,
    authors: rec.authorString ?? null,
    abstract: abstractToText(rec.abstractText),
    openAccess,
    license: rec.license ?? null,
    fullTextStatus,
    sections,
    truncated,
    links: {
      publisher: doiLink(doi),
      pubmed: pubmedLink(pmid),
      pmc: pmcLink(pmcid),
      europepmc: pmcid
        ? `https://europepmc.org/article/PMC/${pmcid}`
        : pmid ? `https://europepmc.org/article/MED/${pmid}` : null,
    },
  };
}

// ─── Route ──────────────────────────────────────────────────────────────

export function registerLiteratureFulltextRoutes(
  app: Express,
  authenticate: RequestHandler,
  fetcher: () => Fetch = () => globalThis.fetch,
) {
  const cache = new Map<string, { at: number; value: FulltextResponse }>();

  app.get("/api/literature/fulltext", authenticate, async (req, res) => {
    const ids = normaliseIds(req.query as Record<string, unknown>);
    if (!ids) {
      res.status(400).json({ error: "invalid_source_id", message: "Provide a valid pmid, pmcid or doi." });
      return;
    }
    const key = JSON.stringify([ids.pmcid ?? "", ids.pmid ?? "", ids.doi?.toLowerCase() ?? ""]);
    const hit = cache.get(key);
    if (hit && Date.now() - hit.at < CACHE_TTL_MS) {
      res.json(hit.value);
      return;
    }
    try {
      const value = await resolveFulltext(ids, fetcher());
      if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value as string);
      cache.set(key, { at: Date.now(), value });
      res.json(value);
    } catch (err: any) {
      console.warn("[literature-fulltext] Europe PMC lookup failed:", err?.message ?? err);
      res.status(502).json({ error: "literature_source_unavailable" });
    }
  });
}
