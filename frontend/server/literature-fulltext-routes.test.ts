/**
 * Contract tests for GET /api/literature/fulltext (citation "Read").
 *
 * Upstream responses are RECORDED Europe PMC REST payloads (2026-11-10,
 * unmodified) under server/__fixtures__/europepmc/:
 *   search_pmid_25516281.json        search?query=EXT_ID:25516281 AND SRC:MED&resultType=core&format=json
 *                                    (DESeq2, Love et al. 2014 — open access, PMC4302049)
 *   PMC4302049_fullTextXML.xml       PMC4302049/fullTextXML (JATS)
 *   search_doi_cell_2011_02_013.json search?query=DOI:"10.1016/j.cell.2011.02.013" (closed access)
 *   search_doi_not_indexed.json      search?query=DOI:"10.1302/3114-221593" (hitCount 0 — an EPAR-test citation)
 * global fetch is replaced by a router over those files; the route runs for real
 * over loopback HTTP with an injected auth gate.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import express from "express";
import type { Server } from "node:http";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  registerLiteratureFulltextRoutes,
  normaliseIds,
  buildSearchQuery,
  parseJatsBody,
  abstractToText,
} from "./literature-fulltext-routes";

const FIX = path.join(path.dirname(fileURLToPath(import.meta.url)), "__fixtures__", "europepmc");
const fixture = (name: string) => readFileSync(path.join(FIX, name), "utf8");

const httpFetch = globalThis.fetch;
let server: Server;
let port: number;
let upstreamCalls: string[] = [];
let failFullText = false;

function fakeEuropePmc(url: string): Response {
  upstreamCalls.push(url);
  const u = new URL(url);
  if (u.pathname.endsWith("/PMC4302049/fullTextXML")) {
    if (failFullText) return new Response("", { status: 500 });
    return new Response(fixture("PMC4302049_fullTextXML.xml"), { status: 200, headers: { "Content-Type": "application/xml" } });
  }
  if (u.pathname.endsWith("/search")) {
    const q = u.searchParams.get("query") || "";
    const body = q === "EXT_ID:25516281 AND SRC:MED" || q === "PMCID:PMC4302049"
      ? fixture("search_pmid_25516281.json")
      : q === 'DOI:"10.1016/j.cell.2011.02.013"'
      ? fixture("search_doi_cell_2011_02_013.json")
      : fixture("search_doi_not_indexed.json");
    return new Response(body, { status: 200, headers: { "Content-Type": "application/json" } });
  }
  return new Response("not found", { status: 404 });
}

async function get(qs: string, auth = true) {
  const res = await httpFetch(`http://127.0.0.1:${port}/api/literature/fulltext?${qs}`, {
    headers: auth ? { authorization: "unit-user" } : {},
  });
  return { status: res.status, body: res.status === 200 || res.status >= 400 ? await res.json().catch(() => null) : null };
}

beforeEach(async () => {
  upstreamCalls = [];
  failFullText = false;
  const app = express();
  registerLiteratureFulltextRoutes(
    app,
    (req, res, next) => { if (!req.headers.authorization) { res.status(401).json({ error: "unauthenticated" }); return; } next(); },
    () => (async (url: any) => fakeEuropePmc(String(url))) as typeof fetch,
  );
  await new Promise<void>((resolve) => { server = app.listen(0, "127.0.0.1", resolve); });
  port = (server.address() as any).port;
});
afterEach(async () => { await new Promise<void>((r) => server.close(() => r())); vi.restoreAllMocks(); });

describe("GET /api/literature/fulltext — contract", () => {
  it("401 without authentication (never reaches Europe PMC)", async () => {
    const r = await get("pmid=25516281", false);
    expect(r.status).toBe(401);
    expect(upstreamCalls).toHaveLength(0);
  });

  it("400 for no / malformed ids", async () => {
    expect((await get("")).status).toBe(400);
    expect((await get("pmid=abc&doi=nope")).body).toEqual(expect.objectContaining({ error: "invalid_source_id" }));
  });

  it("open-access PMID → abstract + parsed full-text sections + links", async () => {
    const r = await get("pmid=25516281");
    expect(r.status).toBe(200);
    const b = r.body;
    expect(b).toMatchObject({
      found: true, source: "europepmc", openAccess: true, fullTextStatus: "available", license: "cc by",
      ids: { pmid: "25516281", pmcid: "PMC4302049", doi: "10.1186/s13059-014-0550-8" },
      year: "2014",
      links: { publisher: "https://doi.org/10.1186/s13059-014-0550-8", europepmc: "https://europepmc.org/article/PMC/PMC4302049" },
    });
    expect(b.title).toMatch(/DESeq2/);
    expect(b.abstract).toMatch(/^In comparative high-throughput sequencing assays/);
    expect(b.abstract).not.toMatch(/<[a-z]/i);
    const headings = b.sections.map((s: any) => s.heading);
    expect(headings).toContain("Background");
    expect(headings).toContain("Results and discussion");
    const text = b.sections.flatMap((s: any) => s.paragraphs).join("\n");
    expect(text.length).toBeGreaterThan(20_000);
    expect(text).not.toMatch(/<\/?(p|xref|italic|mml:)/);
    // search, then fullTextXML — exactly two upstream calls.
    expect(upstreamCalls).toHaveLength(2);
    expect(upstreamCalls[1]).toContain("/PMC4302049/fullTextXML");
  });

  it("caches a resolved source (second request does not hit Europe PMC)", async () => {
    await get("pmid=25516281");
    await get("pmid=25516281");
    expect(upstreamCalls).toHaveLength(2);
  });

  it("closed-access DOI → abstract only, honest not_open_access, no full-text fetch", async () => {
    const r = await get("doi=10.1016/j.cell.2011.02.013");
    expect(r.body).toMatchObject({ found: true, openAccess: false, fullTextStatus: "not_open_access", sections: [] });
    expect(r.body.title).toMatch(/Hallmarks of cancer/);
    expect(r.body.abstract?.length).toBeGreaterThan(200);
    expect(r.body.links.publisher).toBe("https://doi.org/10.1016/j.cell.2011.02.013");
    expect(upstreamCalls).toHaveLength(1);
  });

  it("not indexed → not_found with the publisher link, no fabricated body", async () => {
    const r = await get("doi=10.1302/3114-221593");
    expect(r.body).toMatchObject({ found: false, fullTextStatus: "not_found", abstract: null, sections: [] });
    expect(r.body.links.publisher).toBe("https://doi.org/10.1302/3114-221593");
  });

  it("OA full-text leg failing degrades to the abstract with status 'unavailable'", async () => {
    failFullText = true;
    const r = await get("pmcid=PMC4302049");
    expect(r.body).toMatchObject({ openAccess: true, fullTextStatus: "unavailable", sections: [] });
    expect(r.body.abstract).toBeTruthy();
  });

  it("502 when the Europe PMC search itself fails", async () => {
    server.close();
    const app = express();
    registerLiteratureFulltextRoutes(app, (_q, _s, n) => n(), () => (async () => new Response("", { status: 503 })) as any);
    await new Promise<void>((resolve) => { server = app.listen(0, "127.0.0.1", resolve); });
    port = (server.address() as any).port;
    vi.spyOn(console, "warn").mockImplementation(() => {});
    expect((await get("pmid=1")).status).toBe(502);
  });
});

describe("helpers", () => {
  it("normaliseIds accepts real ids and rejects query-breaking input", () => {
    expect(normaliseIds({ pmid: "123", pmcid: "4302049", doi: "https://doi.org/10.1/x" })).toEqual({ pmid: "123", pmcid: "PMC4302049", doi: "10.1/x" });
    expect(normaliseIds({ doi: '10.1/x" OR 1' })).toBeNull();
    expect(normaliseIds({ pmid: "12a" })).toBeNull();
  });
  it("buildSearchQuery prefers PMCID, then PMID, then quoted DOI", () => {
    expect(buildSearchQuery({ pmcid: "PMC1", pmid: "2", doi: "10.1/x" })).toBe("PMCID:PMC1");
    expect(buildSearchQuery({ pmid: "2", doi: "10.1/x" })).toBe("EXT_ID:2 AND SRC:MED");
    expect(buildSearchQuery({ doi: "10.1/x" })).toBe('DOI:"10.1/x"');
  });
  it("parseJatsBody drops figures/tables/formulas and keeps section prose", () => {
    const { sections } = parseJatsBody(`<article><body><sec><title>Intro</title><p>Hello <italic>world</italic> &amp; more.</p>
      <fig><caption><title>Fig</title><p>caption text</p></caption></fig><table-wrap><p>cell</p></table-wrap></sec></body></article>`);
    expect(sections).toEqual([{ heading: "Intro", paragraphs: ["Hello world & more."] }]);
  });
  it("abstractToText keeps section labels as lines and strips tags", () => {
    expect(abstractToText("<h4>Background</h4>Some <i>text</i>.")).toBe("Background\nSome text.");
  });
});
