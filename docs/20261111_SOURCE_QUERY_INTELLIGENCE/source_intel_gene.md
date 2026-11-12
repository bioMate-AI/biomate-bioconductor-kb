# Source Intelligence — Gene / Genomics Cluster

Sources: **NCBI Gene, Ensembl, STRING, mygene.info**
Date: 2026-11-11 · Audit of BioMate federated query layer
All endpoints below VERIFIED live with `curl -A "BioMate/1.0"` (results summarized inline).

Code reviewed:
- `backend/lib/galaxy/ai/federated_query.py` — `_fetch_ncbi_gene`, `_fetch_ensembl`, `_fetch_string`, `_FETCHERS`, `ENTITY_SOURCES`
- `backend/lib/galaxy/ai/data_sources.py` — registry rows (lines 62–77)
- `backend/lib/galaxy/ai/agents/research_agent.py` — `lookup_mygene` (637), `lookup_ensembl_ids` (473), `search_ensembl_genes` (495), `lookup_omim_gene` (787)
- `backend/lib/galaxy/ai/skills/evidence-source-selection.md` — facet→source map (gene identity baseline = NCBI Gene, Ensembl, UniProt, GO, STRING)

---

## 1. mygene.info

### 1.1 What it is / base URL / keys
High-throughput gene-annotation query hub (BioThings API, Su/Wu lab, Scripps). Aggregates NCBI Gene, Ensembl, UniProt, HGNC, OMIM, HomoloGene, RefSeq into one JSON record keyed by Entrez id. **No key, no account.** Base: `https://mygene.info/v3`. Generous rate limits (~1000 req/min); POST batch endpoints preferred for N>1. This is the single best "symbol → everything" resolver in the cluster.

### 1.2 Key endpoints + which use case
| Endpoint | Use case |
|---|---|
| `GET /v3/query?q=symbol:BRCA1&species=human` | symbol → Entrez/Ensembl/UniProt resolution (the core alias-safe resolver) |
| `GET /v3/query?q=<term>&scopes=symbol,alias,...` | **alias-tolerant** resolution (p53, BCR-ABL, CD antigens) |
| `POST /v3/query` (body `q=BRCA1,TP53,p53&scopes=symbol,alias`) | **batch** resolve a list in ONE request |
| `GET /v3/gene/<entrez|ENSG>?fields=...` | direct annotation fetch by id |
| field `homologene` / `pantherdb.ortholog` | **orthologs** (species taxid → gene id pairs) — no separate call |
| field `ensembl.gene`, `uniprot.Swiss-Prot`, `entrezgene` | cross-refs / resolution chain in one hop |

Resolution chain: one `symbol:` query returns `entrezgene` + `ensembl.gene` + `uniprot.Swiss-Prot` simultaneously → feeds STRING, UniProt, Ensembl downstream without extra calls.

### 1.3 Field constraints / alias handling (VERIFIED)
- `GET /v3/query?q=symbol:BRCA1&fields=symbol,name,entrezgene,ensembl.gene,uniprot&species=human&size=1`
  → `{entrezgene:"672", ensembl.gene:"ENSG00000012048", uniprot.Swiss-Prot:"P38398", symbol:"BRCA1"}` — one call, full cross-ref set.
- **Alias miss demonstrated:** `q=symbol:p53` → `total:0, hits:[]`. `q=p53&scopes=symbol,alias` → TP53 (7157). So symbol-only scope silently drops common aliases.
- **Fusion name:** `q=BCR-ABL` (free text) → noise (LOC107963947…). `q=alias:BCR-ABL` → **ABL1 (entrez 25)** cleanly.
- **Batch POST** `q=BRCA1,TP53,p53&scopes=symbol,alias` → 3 rows resolved incl. p53→TP53 in a single HTTP round-trip.
- `homologene.genes` gives ortholog gene ids across taxa (e.g. BRCA1: mouse 12189, rat 497672, macaque 712634).

### 1.4 Pitfalls
- `species` defaults to **all species** if omitted → cross-species collisions; always set `species=human` (or the task species).
- `q=symbol:X` is exact-symbol only → aliases/fusions miss (shown above). Must add `scopes=symbol,alias,retired,other_names`.
- Looping `size=1` per identifier wastes N requests vs one POST batch.

### 1.5 What BioMate does now + GAPS (`lookup_mygene`, research_agent.py:637)
- Uses `GET /v3/query?q=symbol:<ident>&species=human&size=1` **one request per identifier** in a loop (max 10). ENSG/numeric ids go via POST `/v3/gene`.
- **GAP A (alias miss):** scope is `symbol:` only → p53, BCR-ABL, HER2, CD20, etc. return nothing. Highest-impact gap.
- **GAP B (no batch):** symbol path loops 1-by-1; should POST `/v3/query` with comma-joined `q` + `scopes`.
- **GAP C:** default fields don't include `ensembl.gene`/`entrezgene`/`uniprot` → the resolution chain isn't captured, so STRING/UniProt/Ensembl fetchers re-resolve the symbol independently.
- Note: `lookup_mygene` is a research_agent helper and is **NOT wired into federated_query** — the federated `gene` fan-out uses `_fetch_ncbi_gene`/`_fetch_ensembl` which have their own (weaker) resolution.

---

## 2. NCBI Gene (E-utilities)

### 2.1 What it is / base URL / keys
Authoritative gene records (Entrez Gene) via E-utilities. Base: `https://eutils.ncbi.nlm.nih.gov/entrez/eutils`. Keyless = **3 req/s**; with optional `&api_key=<key>` = **10 req/s**. Periodic maintenance → 429/503 (must be distinguished from empty results).

### 2.2 Key endpoints + use case
| Endpoint | Use case |
|---|---|
| `esearch.fcgi?db=gene&term=...` | symbol/name → Entrez UID(s) |
| `esummary.fcgi?db=gene&id=...` | UID → name, description, aliases, maplocation, organism |
| `efetch.fcgi?db=gene&id=...&rettype=gene_table` | full record / exon structure |
| `elink.fcgi?dbfrom=gene&db=...` | cross-refs (gene→snp, gene→omim, gene→pubmed) |
| `db=gene&term=X[sym]+AND+alias` | name/alias search |

### 2.3 Filters / synonyms (VERIFIED)
- `esearch.fcgi?db=gene&term=BRCA1[gene] AND Homo sapiens[organism]&retmode=json`
  → `idlist:["672"]` (exactly one). The `[gene]`/`[sym]` and `[organism]` field tags are what make it precise.
- Field tags that raise hit rate: `[sym]` (official symbol), `[gene]`, `[prev]` (previous symbol), `[all]`, `[organism]`. For alias tolerance use `term=p53[all] AND human[organism]` or drop to `[gene]` which already resolves many aliases server-side.

### 2.4 Pitfalls
- **No api_key** → at >3 req/s the whole fan-out gets 429; a federated burst (gene fan-out hits ~9 sources) can trip it. Add `api_key` + jitter.
- Brackets/spaces in `term` must be URL-encoded (unencoded `[` → curl "bad range"; server 400).
- esummary `organism` is a nested dict (`.organism.scientificname`), not a string.
- Maintenance windows return 503 — must `_note_failure` so "0 genes" isn't reported as a clean empty.
- `retmax=5` default returns paralogs/readthroughs; take top hit by relevance, not blindly.

### 2.5 What BioMate does now + GAPS (`_fetch_ncbi_gene`, federated_query.py:296)
- Hardcodes `+Homo+sapiens[organism]` and `[gene]`, esearch→esummary, returns gene_id/symbol/description/organism. Reasonable baseline.
- **GAP D (species hardcoded):** `Homo sapiens` is baked in → mouse/rat/zebrafish gene queries return empty. Should take species from entity extraction (default human).
- **GAP E (no api_key):** no `&api_key=` and no inter-call throttle → 429 risk under fan-out. `_note_failure` path exists for KEGG; esearch/esummary should use the same so rate-limits aren't silent zeros.
- **GAP F (no alias fallback):** `[gene]` only; if 0 hits, no retry on `[all]`/`[prev]`.

---

## 3. Ensembl REST

### 3.1 What it is / base URL / keys
Genome annotation (genes, transcripts, coordinates, xrefs, VEP, orthologs). Base: `https://rest.ensembl.org`. **No key.** Soft rate limit ~15 req/s (sends `Retry-After` 429 with `X-RateLimit-*` headers). GRCh38 default; GRCh37 via `https://grch37.rest.ensembl.org`.

### 3.2 Key endpoints + use case
| Endpoint | Use case |
|---|---|
| `GET /xrefs/symbol/<species>/<symbol>` | symbol → ENSG id (+ LRG) |
| `GET /lookup/symbol/<species>/<symbol>?expand=1` | symbol → ENSG + **coordinates, biotype, strand, canonical transcript** |
| `POST /lookup/id` (body `{"ids":[ENSG...]}`) | **batch** ENSG → symbol/biotype/description |
| `GET /xrefs/id/<ENSG>` | ENSG → UniProt/HGNC/RefSeq cross-refs |
| `GET /homology/symbol/<species>/<symbol>?type=orthologues` | **orthologs** across species |
| `GET /vep/human/hgvs/<hgvs>` | variant consequence (used by `lookup_ensembl_vep`) |
| `GET /overlap/region/...` | features in a locus |

### 3.3 Fields / species (VERIFIED)
- `GET /xrefs/symbol/homo_sapiens/BRCA1` → `[{"type":"gene","id":"ENSG00000012048"},{"type":"gene","id":"LRG_292"}]` — note LRG id mixed in; filter `type==gene` + `id^=ENSG`.
- `GET /lookup/symbol/homo_sapiens/BRCA1` → GRCh38, chr17:43044292-43170245, strand −1, biotype protein_coding, canonical ENST00000357654.9, HGNC:1100. Richer than xrefs for one call.
- `GET /xrefs/symbol/mus_musculus/Brca1` → `ENSMUSG00000017146` — species param works; **case-sensitive symbol** (mouse `Brca1` not `BRCA1`).

### 3.4 Pitfalls
- `xrefs/symbol` returns LRG_* and clone ids alongside the real ENSG → must filter.
- Species-specific symbol casing (human UPPER, mouse Title case); wrong case → empty.
- Default assembly GRCh38; GRCh37/legacy coordinates need the grch37 host.
- `Content-Type`/`Accept: application/json` required or returns XML.
- Ensembl is occasionally slow (11 s observed for xrefs/symbol) — keep a generous timeout.

### 3.5 What BioMate does now + GAPS
- `_fetch_ensembl` (federated_query.py:374): `xrefs/symbol/homo_sapiens/<q>` — only runs if query matches `^[A-Z][A-Z0-9]+$`, returns id+type, no LRG filter, **human hardcoded**.
- `lookup_ensembl_ids` (research_agent.py:473): good — POST `/lookup/id` batch (up to 50), returns symbol/biotype/chr. Keep.
- `search_ensembl_genes` (495): `GET /lookup/symbol` per symbol (loop) — richer but 1-by-1.
- **GAP G:** federated `_fetch_ensembl` is human-only + no LRG filter + regex gate rejects mixed-case/mouse symbols (`^[A-Z][A-Z0-9]+$` drops `Brca1`).
- **GAP H:** no ortholog endpoint wired into fan-out (`/homology/symbol`) despite ortholog being a named use case.

---

## 4. STRING

### 4.1 What it is / base URL / keys
Protein–protein interaction / functional-association network DB. Base: `https://string-db.org/api`. **No key**, but requires `caller_identity` and a **resolved identifier + species** (NCBI taxid). Format in path: `/api/json/<method>` or `/api/tsv/...`.

### 4.2 Key endpoints + use case
| Endpoint | Use case |
|---|---|
| `GET /api/json/get_string_ids?identifiers=TP53&species=9606` | symbol → STRING id (preferredName, ENSP) — resolution only |
| `GET /api/json/interaction_partners?identifiers=TP53&species=9606&limit=N` | **direct interaction partners** of one protein (the "who does X interact with" use case) |
| `GET /api/json/network?identifiers=A%0dB%0dC&species=9606&required_score=700` | **network among a gene set** (edges + per-channel scores) |
| `GET /api/json/enrichment?identifiers=...&species=9606` | GO/KEGG/Reactome enrichment of a gene set |
| `GET /api/image/network?...` | PNG network figure |

### 4.3 Fields / scores (VERIFIED)
- `get_string_ids?identifiers=TP53&species=9606` → `{queryItem:"TP53", stringId:"9606.ENSP00000269305", preferredName:"TP53", annotation:"..."}`. **No `score` field in this response.**
- `interaction_partners?identifiers=TP53&species=9606&limit=3` → rows `{preferredName_A:"TP53", preferredName_B:"SIRT1", score:0.999, nscore,fscore,pscore,ascore,escore,dscore,tscore}` — combined + per-channel confidence (0–1).
- `network?identifiers=TP53` → edges among the neighborhood with same score channels.
- `required_score` (0–1000) filters low-confidence edges; 700 = high confidence (recommended default).

### 4.4 Pitfalls
- **Must resolve first:** passing an ambiguous symbol or wrong species → empty or wrong-organism hits. Always `species=<taxid>` (9606 human) and prefer passing a STRING id / UniProt from mygene.
- `get_string_ids` does NOT return interaction scores — it's resolution only; a "network" use case needs `interaction_partners`/`network`.
- `caller_identity` required by ToS; omitting risks throttling.
- Multi-identifier calls separate ids with `%0d` (CR) in the URL.

### 4.5 What BioMate does now + GAPS (`_fetch_string`, federated_query.py:384)
- Calls `get_string_ids?identifiers=<q>&species=9606&limit=5` and emits `{protein_id, gene, score: p.get("score")}`.
- **GAP I (dead score field):** `get_string_ids` has no `score` key → **`score` is always `None`**. Misleading.
- **GAP J (no network):** STRING is registered as category `interaction` but the fetcher NEVER returns interactions — only resolves ids. For the interaction-network use case it returns no partners. Should, after resolving, call `interaction_partners` (top-N partners + combined score).
- **GAP K (species hardcoded 9606).**

---

## 5. Existing skills / docs to integrate

**Repo:**
- `backend/lib/galaxy/ai/skills/evidence-source-selection.md` — facet→source map; gene-identity baseline already lists NCBI Gene/Ensembl/UniProt/GO/STRING, pathway/network facet lists STRING. Extend with the alias-resolution + STRING-network notes here.
- `backend/lib/galaxy/ai/data_sources.py` — canonical registry; STRING = category `interaction`. Any new endpoint must stay consistent here.
- `backend/lib/galaxy/ai/evidence_source_router.py` (`select_sources`) — deterministic selector the skill mirrors.
- `docs/20260728_UNIFIED_DATA_SOURCE_REGISTRY.md` — registry design.
- `research_agent.py` helpers (`lookup_mygene`, `lookup_ensembl_ids`, `search_ensembl_genes`, `lookup_ensembl_vep`, `lookup_omim_gene`) — mature gene-resolution utilities that should back the federated fetchers instead of the fetchers re-implementing weaker resolution.

**External (cite):**
- NCBI E-utilities: https://www.ncbi.nlm.nih.gov/books/NBK25501/ (api_key, 3→10 req/s, usage guidelines)
- Ensembl REST: https://rest.ensembl.org/documentation (endpoints incl. /homology, /lookup, /xrefs, /vep)
- STRING API: https://string-db.org/help/api/ (get_string_ids, interaction_partners, network, enrichment, caller_identity)
- mygene.info: https://docs.mygene.info/en/latest/doc/query_service.html (scopes, fields, batch POST) and https://docs.mygene.info/en/latest/doc/annotation_service.html
- MCP servers that already wrap these: **BioThings MCP** (mygene/myvariant/mychem), **NCBI/Entrez MCP** (`mcp-ncbi-eutils`), **Ensembl MCP** — candidates to adopt rather than hand-maintain fetchers.

---

## 6. Prioritized fetcher improvements (concrete)

**P0 — alias-safe mygene resolver as the cluster's front door**
Add `scopes=symbol,alias,retired,other_names` + batch POST to `lookup_mygene` and/or a new `_fetch_mygene` in federated_query:
`POST https://mygene.info/v3/query` body `q=<comma-joined>&scopes=symbol,alias,retired&fields=symbol,name,entrezgene,ensembl.gene,uniprot.Swiss-Prot,homologene&species=human`.
Fixes p53, BCR-ABL, HER2, CD20 misses AND emits the full resolution chain (Entrez+ENSG+UniProt) in one call for downstream fetchers. Fixes GAP A/B/C.

**P1 — STRING: return real interactions, not a null score**
After resolving with `get_string_ids`, call
`GET https://string-db.org/api/json/interaction_partners?identifiers=<stringId>&species=<taxid>&limit=10&required_score=700&caller_identity=biomate`
and emit partners with `score`/per-channel values. Drop the dead `p.get("score")` from the resolution step. Fixes GAP I/J.

**P2 — NCBI Gene: api_key + throttle + species + alias fallback**
Append `&api_key=<NCBI_API_KEY env>` (3→10 req/s), route failures through `_note_failure`, parametrize `[organism]` from extracted species, and retry `[all]`/`[prev]` tags on 0 hits. Fixes GAP D/E/F.

**P3 — Ensembl: drop regex gate, filter LRG, parametrize species, switch to lookup/symbol**
Replace `_fetch_ensembl`'s `^[A-Z][A-Z0-9]+$` gate + xrefs/symbol with
`GET /lookup/symbol/<species>/<symbol>?expand=0` (returns ENSG+coords+biotype in one call), filter `object_type==Gene`, default GRCh38. Fixes GAP G.

**P4 — Ortholog use case**
Wire `GET /homology/symbol/<species>/<symbol>?type=orthologues&content-type=application/json` (Ensembl) and/or mygene `homologene` field into the fan-out when the intent is ortholog/cross-species. Fixes GAP H.

**P5 — Make federated fetchers reuse research_agent helpers**
`_fetch_ensembl`/`_fetch_ncbi_gene` should delegate to the mature `search_ensembl_genes`/`lookup_mygene` resolution rather than re-implementing it, so a single alias-handling fix propagates everywhere.
