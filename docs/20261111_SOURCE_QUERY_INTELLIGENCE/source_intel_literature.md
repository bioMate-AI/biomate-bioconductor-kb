# Literature Source Intelligence — BioMate federated query audit
Date: 2026-11-11 · Sources: PubMed, Europe PMC, OpenAlex, Crossref, Semantic Scholar, bioRxiv
Scope: how BioMate queries literature DBs + how to query them intelligently per use case.
All endpoint claims below were VERIFIED with live `curl` on 2026-11-11 (results inline).

## Code under audit
- `backend/lib/galaxy/ai/federated_query.py` — per-source `_fetch_*` + `_FETCHERS` fan-out. Literature sources: `corpus_fs, pubmed, europepmc, biorxiv, semantic_scholar, openalex, crossref` (+ paperclip).
- `backend/lib/galaxy/ai/agents/literature_clients.py` — `PubMedClient` (good throttle+key), `ArxivClient`, `SemanticScholarClient` (gated), `UnifiedLiteratureClient.search_bioinformatics` → routes through `federated_query.iterative_literature_search`.
- `backend/lib/galaxy/ai/agents/research_agent.py` — `_fetch_s2_paper` (S2, key-gated), `_fetch_pmc_fulltext`, PMC PDF/figure fetch via Europe PMC render endpoint.
- `backend/lib/galaxy/ai/evidence_source_router.py` — `LITERATURE_SOURCES = [pubmed, europepmc, semantic_scholar, corpus_fs, paperclip]` (NOTE: omits openalex + crossref + biorxiv that the federated layer supports).
- Skill: `backend/lib/galaxy/ai/skills/evidence-source-selection.md` — facet→source map; "Literature (always): PubMed, Europe PMC, Semantic Scholar, local corpus, Paperclip".

## Cross-cutting findings (the important ones)
1. **Crossref fetcher sends NO `mailto`** → stuck in the public pool at **1 req/s**. Adding `mailto` moves it to the **polite pool at 3 req/s** (VERIFIED below). This is the single cheapest win.
2. **OpenAlex fetcher puts the mailto only inside the User-Agent string, not as the `mailto=` query param.** OpenAlex's documented polite-pool trigger is the `mailto` query param (or `api_key`); relying on UA alone is undocumented/unreliable. Add `&mailto=`.
3. **PubMed in the federated layer (`_fetch_ncbi_entrez`) has no API key, no `tool=`/`email=`, and NO throttle or backoff.** The decomposed recall-widening fires many parallel esearch+esummary calls → bursts straight through NCBI's 3 req/s keyless ceiling → 429/503, especially during the current NCBI maintenance. `PubMedClient` in literature_clients.py HAS a throttle+key path but the federated `search_bioinformatics` path bypasses it.
4. **No retry/backoff anywhere in `_get`/`_post_json`.** A single 429 = that source silently contributes 0 and is marked `error`. There is no `Retry-After` honouring.
5. **Europe PMC fetcher uses a bare keyword query with `resultType=core`** (heavy per-record payload) and no field tags / sort. Europe PMC is keyless, a PubMed superset, and supports rich field-tagged queries — it should be the PRIMARY recall source and absorb load off NCBI.
6. **Dedup is weak**: `_merge_results` dedups by `accession|gene_id|pmid|…|title[:60]`. No DOI normalization (lowercase, strip `https://doi.org/`), so the same paper from Crossref (DOI), OpenAlex (DOI), Europe PMC (PMID+DOI) can survive as 3 rows.

---

## 1. PubMed (NCBI E-utilities)
**What:** NCBI's citation DB (~37M). Base `https://eutils.ncbi.nlm.nih.gov/entrez/eutils`. Keyless **3 req/s**, **10 req/s with `NCBI_API_KEY`** (free). NCBI asks for `tool=` + `email=` on every call. Currently intermittent 429/503 (maintenance) — live test returned 200 at audit time, so it is flaky not down.

**Endpoints → use case:**
- `esearch.fcgi` — keyword search → returns PMIDs. Supports field tags, MeSH, date filters, `sort=relevance|pub_date`.
- `esummary.fcgi` (JSON) — lightweight metadata for PMIDs (title, authors, DOI in `articleids`).
- `efetch.fcgi&retmode=xml` — full abstract + structured authors/journal (what `PubMedClient._parse_pubmed_xml` uses). Right for abstract retrieval.
- by-PMID lookup: esummary/efetch with `id=`. No native DOI lookup (use Europe PMC `DOI:` or Crossref for DOI→record).
- No citation graph, no OA PDF (use Europe PMC/S2/OpenAlex for those).

**Query-quality levers (VERIFIED):**
- MeSH: `"Breast Neoplasms"[MeSH Terms] AND 2024[pdat]` → `count 16205`. **GOTCHA:** MeSH tag only works on real headings. `"BRCA1"[MeSH Terms]` → `count 0, quotedphrasesnotfound` (BRCA1 is a gene/Supplementary Concept, not a MeSH heading). For genes use `[tiab]`: `BRCA1[tiab] AND cancer[tiab]` → `count 19224`. → **rule: never emit `[MeSH Terms]` unless the term is validated against MeSH; default gene/entity terms to `[tiab]`.**
- `sort=pub_date` for recency, `sort=relevance` (default) for precision.
- Date: `&mindate=2020/01/01&maxdate=2024/12/31&datetype=pdat` or inline `2024[pdat]`.
- Add `&api_key=$NCBI_API_KEY&tool=biomate&email=...` to every call.

**Pitfalls:** keyless 3 req/s + maintenance 429/503; MeSH false-negatives on gene symbols; `retmode=json` on efetch is NOT supported for pubmed (must use XML or esummary); decomposed-query burst exceeds rate limit.

**Current BioMate state / GAPS:**
- `_fetch_ncbi_entrez` (federated): esearch→esummary JSON, **no key, no tool/email, no throttle, no backoff, no field tags** (raw query). Biggest rate-limit exposure.
- `PubMedClient` (literature_clients): HAS `_rate_limit_wait` (0.34s keyed/1.0s keyless), email, key, date filters — but the federated `search_bioinformatics` path does NOT use it.
- `_enrich_citation_identifiers` already does title→PMID verify via esearch `[Title]` + esummary fuzzy-match ≥0.85 — good, but also unthrottled (`max_lookups=15` sequential).

## 2. Europe PMC
**What:** EBI's open mirror + superset of PubMed (abstracts + ~5M OA full texts + preprints + patents + agricola). Base `https://www.ebi.ac.uk/europepmc/webservices/rest`. **Keyless, generous limits, no maintenance dependency on NCBI.** Should be BioMate's primary recall engine.

**Endpoints → use case:**
- `/search?query=...&format=json` — keyword + field-tagged search. `resultType=lite` (fast) vs `core` (abstract, full-text URLs, licence, MeSH).
- `/{source}/{id}/fullTextXML` and `/{source}/{id}/textMinedTerms` — full text / entities.
- `europepmc.org/backend/ptpmcrender.fcgi?accid=PMC..&blobtype=pdf` — OA PDF (already used by research_agent).
- by-DOI/PMID: `query=DOI:10...` or `query=EXT_ID:<pmid> AND SRC:MED`.

**Query-quality levers (VERIFIED):**
- Field tags: `TITLE:"CRISPR" AND SRC:MED AND PUB_YEAR:2024` → `hitCount 2386`. Other tags: `AUTH:`, `ABSTRACT:`, `METHODS:`, `AFF:`, `JOURNAL:`, `KW:`.
- Sort: `sort=CITED desc` → `BRCA1 AND cancer` top hit cBioPortal (14,512 cites); `sort=P_PDATE_D desc` for recency.
- OA/PDF filters: `HAS_PDF:y`, `OPEN_ACCESS:y` → `cancer AND HAS_PDF:y AND OPEN_ACCESS:y` → `hitCount 2,233,944`.
- Preprints: `SRC:PPR AND (PUBLISHER:"bioRxiv" OR PUBLISHER:"medRxiv")` (BioMate already uses this for the biorxiv source — good).
- DOI lookup: `DOI:10.1038/nature12373` → returns pmid 23903748, pmcid PMC4221854.
- Pagination: `pageSize` (max 1000) + `cursorMark=*` (use cursorMark, not page number, for deep paging).

**Pitfalls:** `resultType=core` is heavy (don't use it for the recall sweep — use `lite`, then `core` only for the kept set); implicit AND can over-constrain long decomposed queries (same trailing-term problem the iterative loop already mitigates); `*` wildcards need ≥3 leading chars.

**Current BioMate state / GAPS:**
- `_fetch_europepmc`: bare `query={q}&resultType=core&pageSize=5` — no field tags, no sort, core payload. **GAP: not using TITLE:/ABSTRACT:/sort=CITED|P_PDATE_D; not used as the primary high-volume recall source to offload NCBI.**
- `_fetch_biorxiv`: GOOD — correct `SRC:PPR + PUBLISHER` scoping, labels `peer_reviewed:false`.

## 3. OpenAlex
**What:** Open index of ~250M works + authors/institutions/concepts/sources. Base `https://api.openalex.org`. Keyless **100k/day, 10 req/s**; add `mailto=` for the **polite pool** (faster, more reliable) — documented trigger is the `mailto` query param.

**Endpoints → use case:**
- `/works?search=` — relevance keyword search.
- `/works?filter=` — structured filters (recency, OA, concept, institution, type, citations).
- `/works/doi:10...` or `/works/pmid:...` — by-ID lookup.
- `cited_by_count` + `/works?filter=cites:Wxxxx` — citation graph (cites/cited-by).
- `open_access.oa_url` / `best_oa_location.pdf_url` — OA PDF.

**Query-quality levers (VERIFIED):**
- `search=CRISPR gene editing&filter=from_publication_date:2024-01-01,is_oa:true&mailto=test@biomate.ai` → `count 101627`.
- Other filters: `concepts.id:Cxxxx` (topic), `institutions.ror:`, `type:article`, `cited_by_count:>100`, `to_publication_date:`.
- `select=id,title,publication_year,cited_by_count,open_access` to trim payload.
- `sort=cited_by_count:desc` or `publication_date:desc`.

**Pitfalls:** `search` is loose (stems/fuzzy) — tighten with `filter=title.search:` or `filter=default.search:`; concept IDs must be resolved first; polite pool needs the query param not just UA.

**Current BioMate state / GAPS:**
- `_fetch_openalex`: `search={q}&per-page=5&select=...` with mailto **only in User-Agent**, not as `&mailto=` param. **GAP: add `&mailto=`; add `filter=` for recency/OA when the use case asks; use `title.search` for precision-mode.**

## 4. Crossref
**What:** DOI registration agency metadata (~160M works, all publishers). Base `https://api.crossref.org`. Keyless; **public pool 1 req/s**, **polite pool 3 req/s with `mailto`** (VERIFIED), Plus/paid pool higher. Best for DOI↔metadata, cross-publisher coverage, journal articles not in PubMed.

**Endpoints → use case:**
- `/works?query=` (loose) or `/works?query.bibliographic=` (citation-style, higher precision) — keyword search.
- `/works/{doi}` — by-DOI lookup (metadata, references, funder, licence).
- `/works?filter=` — recency/type filters.
- No abstract for most records (abstracts are JATS-XML when present — BioMate already strips tags); no OA PDF directly (has `link`/`license`).

**Query-quality levers (VERIFIED):**
- `query.bibliographic=CRISPR Cas9 genome editing&filter=from-pub-date:2024-01-01,type:journal-article&mailto=test@biomate.ai&select=DOI,title,issued` → `total 58319`, clean DOIs.
- Pool headers VERIFIED: no mailto → `x-rate-limit-limit: 1 / x-api-pool: public-array`; with `mailto` → `x-rate-limit-limit: 3 / x-api-pool: polite-array`.
- `query.bibliographic` > bare `query` for precision; `query.author`, `query.title` for field targeting.
- `sort=published&order=desc` for recency; `sort=is-referenced-by-count&order=desc` for impact.

**Pitfalls:** bare `query` is very loose (ranks on token overlap); abstracts sparse; use `mailto` in BOTH the param and UA. Rate limit is dynamic — honour `X-Rate-Limit-Limit`/`-Interval` headers.

**Current BioMate state / GAPS:**
- `_fetch_crossref`: `query={q}&rows=5&select=...` with **NO mailto anywhere** → public pool 1 req/s. **GAP (highest-value, cheapest): add `&mailto=` + UA mailto; switch `query` → `query.bibliographic`; add `filter=type:journal-article` and optional `from-pub-date` for recency use cases.**

## 5. Semantic Scholar (S2)
**What:** Academic Graph (~220M papers) + citation graph + TLDRs + OA PDFs. Base `https://api.semanticscholar.org/graph/v1`. Keyless **shared pool heavily throttled → 429 on nearly every call** (VERIFIED: keyless `paper/search` → **HTTP 429**). Free key (`x-api-key`) → ~1 req/s dedicated.

**Endpoints → use case:** `/paper/search` (keyword), `/paper/{DOI|PMID|ArXiv|S2}` (by-ID + `references`/`citations` for the citation graph), `openAccessPdf` field (OA PDF), `tldr` (one-line summary). Right for: citation graph, influential-paper ranking, OA PDF discovery — but ONLY with a key.

**Query-quality levers:** `fields=title,authors,year,citationCount,openAccessPdf,tldr,externalIds`; `year=2020-2024`; `fieldsOfStudy=Biology,Medicine`; `openAccessPdf` (presence filter). (Not re-verified live because keyless 429s.)

**Pitfalls:** keyless pool is unusable for bursts; `citationCount` can be `null` (BioMate already coalesces to 0 — good); 429 without `Retry-After` discipline.

**Current BioMate state / GAPS:**
- Correctly **gated OFF without `SEMANTIC_SCHOLAR_API_KEY`** in federated_query (`_KEY_GATED_SOURCES`), literature_clients (`_s2_enabled`), research_agent (`_fetch_s2_paper` returns `[]` without key). This is the right call. **GAP: none urgent — just document that setting the env var re-enables it, and add `tldr` to the fields when it is re-enabled.**

## 6. bioRxiv (+ medRxiv)
**What:** Preprint servers. Native API `https://api.biorxiv.org` is **date-range / DOI only — NO keyword search** (VERIFIED: `/details/biorxiv/2024-01-01/2024-01-02/0` → 30 records by date, no query param). Therefore keyword preprint search must go through Europe PMC `SRC:PPR`.

**Endpoints → use case:** native API only for: "what dropped on date X", DOI→metadata, published-version linkage (`/details`, `/pubs`). Keyword/topic preprint search → **Europe PMC** `SRC:PPR AND PUBLISHER:"bioRxiv"`. Preprints are NOT peer-reviewed — must be labelled.

**Pitfalls:** no relevance search natively; preprints unreviewed (provenance label mandatory); same paper later appears as a journal article (dedup across preprint+published via DOI).

**Current BioMate state / GAPS:**
- `_fetch_biorxiv` routes through Europe PMC with correct `SRC:PPR` scoping and `peer_reviewed:false` label — **correct design, no gap** beyond the shared dedup-by-DOI improvement.

---

## Existing skills / docs to integrate
**Repo:**
- `backend/lib/galaxy/ai/skills/evidence-source-selection.md` — facet→source map; the human companion of `evidence_source_router.select_sources`. UPDATE: its literature row and `LITERATURE_SOURCES` omit OpenAlex, Crossref, bioRxiv that the federated layer now supports — align them.
- `backend/lib/galaxy/ai/evidence_source_router.py` — `LITERATURE_SOURCES` list (add openalex/crossref/biorxiv for recall use cases).
- `docs/20260728_UNIFIED_DATA_SOURCE_REGISTRY.md`, `docs/20260613_BIOC_KB_SOURCE_MAP.md`, `docs/20260506_GLP_PUBLIC_DATA_SOURCES.md` — source registries to cross-reference.
- Memory: `project_evidence_source_selection.md` (intent→source router + federated wire; "NEEDS backend sync"), `project_research_confabulation.md` (research_query invents PMIDs → verify-IDs path), `project_data_source_fragmentation.md` (60+ sources, chat sees 20).

**External (authoritative):**
- NCBI E-utils: https://www.ncbi.nlm.nih.gov/books/NBK25497/ (usage guidelines, api_key, 10 req/s, tool/email).
- Europe PMC REST + query syntax: https://europepmc.org/RestfulWebService ; fields/sort: https://europepmc.org/Help#mostofsearch and https://europepmc.org/searchsyntax
- OpenAlex docs: https://docs.openalex.org/ ; polite pool: https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication#the-polite-pool ; filters: https://docs.openalex.org/api-entities/works/filter-works
- Crossref REST: https://api.crossref.org/swagger-ui/index.html ; etiquette/polite pool: https://github.com/CrossRef/rest-api-doc#etiquette
- Semantic Scholar: https://api.semanticscholar.org/api-docs/ ; key request: https://www.semanticscholar.org/product/api#api-key
- bioRxiv API: https://api.biorxiv.org/ (details/pubs; no keyword search).
- MCP servers to consider: `PubMed MCP`, `Europe PMC MCP`, `OpenAlex MCP` (community) — but BioMate's own fetchers are fine; these are reference only.

---

## Prioritized concrete improvements
**P0 — rate-limit/polite-pool wins (cheap, high-value):**
1. **Crossref `mailto`** — in `_fetch_crossref`, append `&mailto=admin@biomate.ai` to the URL AND set UA `BioMate/1.0 (mailto:admin@biomate.ai)`. Moves 1→3 req/s (VERIFIED pool flip). Also switch `query=` → `query.bibliographic=`.
2. **OpenAlex `mailto` param** — in `_fetch_openalex`, add `&mailto=admin@biomate.ai` as a query param (not just UA). Guarantees polite pool.
3. **NCBI throttle + key + backoff** — route federated PubMed/dbSNP/ClinVar through a shared token-bucket (3 req/s keyless, 10 with `NCBI_API_KEY`), add `&api_key=&tool=biomate&email=` when key present, and add `Retry-After`-aware exponential backoff (1 retry on 429/503) in `_get`/`_post_json`. This is what the decomposed-query burst most needs.

**P1 — recall/precision quality:**
4. **Prefer Europe PMC field-tagged queries** — in `_fetch_europepmc`, use `resultType=lite` for the sweep, add `sort=CITED desc` (impact) or `P_PDATE_D desc` (recency) per use-case, and emit `TITLE:`/`ABSTRACT:` tags when the intent is precise. Make Europe PMC the primary high-volume recall source so NCBI load drops.
5. **PubMed MeSH guard** — never emit `[MeSH Terms]` for unvalidated terms (gene symbols 0-hit); default to `[tiab]`; only use `[MeSH Terms]` for validated headings (deterministic rule, no LLM).
6. **Shared backoff in `_get`/`_post_json`** — honour `Retry-After`, 1–2 retries with jitter on 429/503; applies to all sources, not just literature.

**P2 — dedup/merge:**
7. **DOI/PMID-normalized dedup** in `_merge_results` — normalize DOI (lowercase, strip `https://doi.org/` prefix) and unify on DOI→PMID→normalized-title so Crossref/OpenAlex/Europe PMC duplicates of one paper collapse to one row (including preprint↔published linkage).
8. **Align routers** — add `openalex`, `crossref` (and preprint `biorxiv` when recency matters) to `evidence_source_router.LITERATURE_SOURCES` and the evidence-source-selection skill's literature row.

**Per-use-case source selection (summary):**
- Precise/known-item (DOI/PMID/title): Europe PMC `DOI:`/`EXT_ID:` or Crossref `/works/{doi}` — not the recall sweep.
- Broad recall (new topic): Europe PMC `lite` (primary) + OpenAlex (filters) + Crossref polite pool; PubMed throttled as corroboration.
- Recency ("latest work"): Europe PMC `sort=P_PDATE_D desc`, OpenAlex `from_publication_date` filter, bioRxiv/medRxiv via `SRC:PPR` (labelled unreviewed).
- Impact/seminal: Europe PMC `sort=CITED desc`, OpenAlex `cited_by_count:desc`, S2 citation graph (keyed).
- OA full text / PDF: Europe PMC `HAS_PDF:y OPEN_ACCESS:y` + `ptpmcrender.fcgi`, OpenAlex `best_oa_location.pdf_url`, S2 `openAccessPdf` (keyed).
- Citation graph: S2 `/paper/{id}/citations|references` (keyed) or OpenAlex `cites:`/`cited_by`.
