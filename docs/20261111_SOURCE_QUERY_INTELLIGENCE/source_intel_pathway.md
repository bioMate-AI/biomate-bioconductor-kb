# Source Intelligence — Pathway / Function / Ontology cluster (KEGG, Reactome, GO, HPO)

Audit date: 2026-11-11. Target file: `backend/lib/galaxy/ai/federated_query.py`
(`_fetch_kegg` L392, `_fetch_reactome` L415, `_fetch_go` L426, `_fetch_hpo` L441).
Registry: `backend/lib/galaxy/ai/data_sources.py` L78–85. All curl verified with
`-A "BioMate/1.0"`. `_get()` (L220) JSON-decodes the body and returns `None` on any
error; `_run_fetcher` (L206) turns a swallowed error + empty results into `status:error`.

## TL;DR — 2 of 4 fetchers are effectively BROKEN
- **HPO**: queries `hpo.jax.org/api/hpo/search` which now serves the Angular SPA **HTML**,
  not JSON → `_get` fails to parse → always 0 results + recorded transport failure.
- **GO**: `search/entity/autocomplete?ontology=go` returns **gene products** (often
  non-human, e.g. *Yarrowia lipolytica*), and the `id` field is a **hex-encoded garbage
  string**, not a `GO:` id. Users get junk ids and wrong-species labels.
- **KEGG** & **Reactome** work but are shallow: keyword search only, no gene→pathway
  resolution chain, no species filter, no pathway→gene expansion.

---

## 1. KEGG

**What / API / licensing.** Kyoto Encyclopedia of Genes and Genomes — curated pathway
maps, genes, compounds, reactions, diseases, drugs. REST base `https://rest.kegg.jp/`.
Keyless, no account. **Licensing caveat (important):** KEGG data/REST is free for
*academic* use only; commercial use requires a paid KEGG FTP/API subscription from
Pathway Solutions / GenomeNet. No published hard rate limit, but the terms ask for
≤ ~3 requests/sec and prohibit bulk scraping; heavy automated use can get an IP blocked.
BioMate should cache aggressively and throttle. All KEGG responses are **TAB-separated
plain text, never JSON** — cannot go through `_get()`; `_fetch_kegg` already special-cases
this with a raw `urlopen`.

**Key endpoints + which use case (verified):**
| Use case | Endpoint | Verified result |
|---|---|---|
| text → pathway (current) | `find/pathway/{text}` | `glycolysis` → `map00010  Glycolysis / Gluconeogenesis` |
| symbol → KEGG gene id | `find/genes/{sym}+{organism}` | `TP53+human` → hits (noisy, cross-species) |
| NCBI GeneID → KEGG id | `conv/hsa/ncbi-geneid:{id}` | `7157` → `hsa:7157` (clean, preferred resolver) |
| **gene → pathways** | `link/pathway/{kegg_gene_id}` | `hsa:3643` → `path:hsa04010`, `hsa04014`, … |
| **pathway → genes** | `link/{org}/{pathway}` | `hsa00010` → `hsa:10327`, `hsa:124`, … |
| pathway/gene detail | `get/{id}` | flat-file record (NAME, CLASS, GENE, etc.) |

**Identifier chain.** KEGG does **not** use HGNC symbols. gene→pathway needs a KEGG gene
id `hsa:<EntrezID>`. Resolution chain: symbol → Entrez (via NCBI Gene fetcher already in
the fan-out, or `find/genes`) → `conv/hsa/ncbi-geneid:<entrez>` → `link/pathway/hsa:<id>`.
`find/pathway/<text>` returns generic reference maps (`map#####`); to get the human,
gene-annotated map, swap `map`→`hsa`.

**Pitfalls.** TSV not JSON; `find/genes` is noisy and cross-species (verified: `TP53
human` top hit was a *chiton*); `map#####` ≠ `hsa#####`; no species filter on `find`;
commercial-use licensing; silent IP throttle.

**CURRENT fetcher + gaps.** `_fetch_kegg` does ONLY `find/pathway/{query}` and returns
up to 5 `{pathway_id, name}` reference maps. **Gaps:** (a) no gene→pathway — the single
most common pathway question ("what pathways is GENE in?") is unanswerable; (b) no
ID resolution (symbol/Entrez → `hsa:`); (c) no pathway→genes expansion for enrichment
context; (d) no `get` detail; (e) returns `map` ids, not species-specific `hsa`.

---

## 2. Reactome

**What / API.** Curated, peer-reviewed human pathway knowledgebase (plus orthology-
inferred species). ContentService base `https://reactome.org/ContentService/`. Keyless,
JSON, no documented hard rate limit (be polite). AnalysisService
`https://reactome.org/AnalysisService/` provides over-representation / expression
enrichment from a gene/ID list.

**Key endpoints + which use case (verified):**
| Use case | Endpoint | Verified result |
|---|---|---|
| text → pathway (current) | `search/query?query={t}&types=Pathway` | `glycolysis` → `R-HSA-70171 Glycolysis` |
| **gene/protein → pathways** | `data/mapping/UniProt/{acc}/pathways?species=9606` | `P04637` → list of TP53 pathways |
| pathway → sub-events/reactions | `data/pathway/{stId}/containedEvents` | `R-HSA-70171` → child reactions |
| pathway → participating molecules | `data/participants/{stId}` | molecules in event |
| **enrichment from gene list** | `AnalysisService/identifiers/projection` (POST) | over-representation p/FDR per pathway |

**Identifier chain.** Search is free-text (keyless, any name). Structured
gene→pathway mapping wants a **UniProt accession** (or other supported db via
`data/mapping/{resource}/{id}/pathways`); resolution: symbol → UniProt (UniProt fetcher
already in fan-out) → mapping. `stId` = stable id `R-HSA-#####`; `species=9606` (NCBI
taxon) filters to human.

**Pitfalls.** Search returns highlighted HTML spans in `name` (`<span class="highlighting">`
— must strip for display). No species filter in current call → non-human orthologs leak in.
`search/query` groups hits under `results[].entries[]` (current code handles this). Analysis
service is POST (needs `_post_json`, already available L235).

**CURRENT fetcher + gaps.** `_fetch_reactome` does ONLY `search/query?types=Pathway`,
5 results. **Gaps:** (a) no `species=Homo sapiens` / `&cluster=true` filter → noise;
(b) no gene→pathway mapping; (c) no pathway expansion (containedEvents/participants);
(d) no AnalysisService enrichment — the whole reason systems-biology users pick Reactome;
(e) does not strip `<span>` markup from names.

---

## 3. Gene Ontology (GO)

**What / API.** Controlled vocabulary of gene function across 3 aspects (BP/MF/CC) plus
gene→term annotations (GOA). Two usable APIs: **geneontology.org** (`api.geneontology.org`,
AmiGO/Solr-backed) and **EBI QuickGO** (`https://www.ebi.ac.uk/QuickGO/services/`). Both
keyless JSON.

**Key endpoints + which use case (verified):**
| Use case | Endpoint | Verified |
|---|---|---|
| GO id → term (current) | geneontology `api/ontology/term/{GO:id}` | `GO:0006096` → "glycolytic process" + def ✓ |
| **text → GO term (CLEAN)** | QuickGO `ontology/go/search?query={t}&limit=5` | `glycolysis` → `GO:0006096`, clean ids ✓ |
| GO id → term (clean, QuickGO) | QuickGO `ontology/go/terms/{GO:id}` | `GO:0006096` → name+definition+aspect ✓ |
| **gene → GO annotations** | QuickGO `annotation/search?geneProductId={UniProt}&limit=` | `P04637` → 1043 annotations, aspect/evidence ✓ |
| term → ancestors/children | QuickGO `ontology/go/terms/{id}/ancestors` (or `/children`) | hierarchy for enrichment context |

**Identifier chain.** Term lookup wants `GO:#######`. gene→GO wants a **UniProtKB
accession** (`geneProductId=UniProtKB:P04637`) or other GOA-supported id; resolution:
symbol → UniProt → QuickGO annotation. Aspect filter `aspect=biological_process|
molecular_function|cellular_component` narrows relevance.

**Pitfalls (the current bug).** geneontology.org `search/entity/autocomplete?ontology=go`
does **NOT** return GO terms — it returns **bioentities (gene products)**. Verified: the
top `glycolysis` hit is `YALI0_B02728g` (*Yarrowia lipolytica*), and `docs[].id` is a
**hex-encoded blob** (`556e6950726f744b42...`), not a `GO:` id. The current fetcher maps
`go_id = d.get("id")` → emits garbage ids and wrong-species gene names. The GO-id branch
(`^GO:\d+$`) works correctly; only the text-search branch is broken.

**CURRENT fetcher + gaps.** `_fetch_go`: if query matches `GO:\d+` → geneontology term
lookup (OK); else → broken autocomplete. **Gaps:** (a) text search returns gene products
with garbage ids → should use QuickGO `ontology/go/search`; (b) no gene→GO annotation
retrieval (QuickGO `annotation/search`); (c) no aspect filter; (d) no ancestor/child
hierarchy for enrichment context.

---

## 4. Human Phenotype Ontology (HPO)

**What / API.** Standardized vocabulary of phenotypic abnormalities in human disease, with
disease↔phenotype↔gene annotations. **The hpo.jax.org REST API was retired** — the live
API is now `https://ontology.jax.org/api/` (HPO/Mondo/Maxo). For phenotype→gene / disease
associations, **Monarch Initiative** `https://api-v3.monarchinitiative.org/v3/api/` is the
richer source. All keyless JSON.

**Key endpoints + which use case (verified):**
| Use case | Endpoint | Verified |
|---|---|---|
| text → HP term (FIX) | `ontology.jax.org/api/hp/search?q={t}&limit=5` | `seizure` → `HP:0007359 Focal-onset seizure` + def ✓ |
| HP id → term detail | `ontology.jax.org/api/hp/terms/{HP:id}` | term metadata |
| **phenotype → diseases** | `ontology.jax.org/api/network/annotation/{HP:id}` | `HP:0001250` → OMIM disease list ✓ |
| **phenotype → genes** | Monarch `v3/api/entity/{HP:id}/biolink:GeneToPhenotypicFeatureAssociation` | `HP:0001250` → 3293 gene assocs ✓ |
| disease/term search (cross-ontology) | Monarch `v3/api/search?q={t}&category=biolink:Disease` | `Marfan syndrome` → `MONDO:0007947` ✓ |

**Response schema.** `ontology.jax.org/api/hp/search` returns `{"terms":[{"id","name",
"definition",...}]}` — **same field names the current fetcher already reads** (`id/name/
definition`). So the HPO text-search fix is essentially a **one-line URL swap** +
`max`→`limit`, `&category=terms` dropped.

**Identifier chain.** HP terms = `HP:#######`. phenotype→gene goes through Monarch (returns
NCBIGene/HGNC). disease ids are OMIM/Orphanet/MONDO.

**Pitfalls (the current bug).** `hpo.jax.org/api/hpo/search?...` now returns the SPA
**HTML document** (verified: `<!doctype html>…<title>Human Phenotype Ontology</title>`).
`_get` tries `json.loads` → raises → returns `None` → fetcher emits 0 results AND
`_run_fetcher` tags it `status:error` on every call. HPO is 100% non-functional today.

**CURRENT fetcher + gaps.** `_fetch_hpo` hits the dead URL. **Gaps:** (a) wrong/dead
host; (b) no phenotype→gene (the key clinical-genomics use case); (c) no
phenotype→disease; (d) no Monarch disease/MONDO search; (e) registry maps HPO only to
`["disease"]` entity — should also serve `phenotype`/`gene` facets.

---

## 5. Existing skills / docs to integrate

**Repo (good existing asset):**
- `backend/lib/galaxy/ai/skills/evidence-source-selection.md` — has the facet→source table;
  the **Pathway / network / signalling** facet already lists `KEGG, Reactome, GO, STRING`,
  and **Disease / phenotype** lists `HPO, OMIM`. This is the human-readable companion of
  `galaxy.ai.evidence_source_router.select_sources`. Any new fetcher capability should be
  reflected here (it is the single source of truth alongside `data_sources.py`).
- No per-source fetcher design docs exist for KEGG/Reactome/GO/HPO. `docs/` has
  enrichment/knowledge docs (`20260608_BIOC_STEP_METADATA_VIZ_QC_ENRICHMENT.md`,
  `20260929_METABOANALYSTR_WORKFLOW_SUITE.md`) but nothing documenting the federated
  fetchers — a gap worth a short design note.
- `docs/20261111_EVIDENCE_PIPELINE_AND_UI_SESSION.md` and
  `20261111_ENTITY_CLAIM_VALIDATION_SPEC.md` reference `federated_query` — align there.

**External docs (cite):**
- KEGG REST: https://www.kegg.jp/kegg/rest/keggapi.html (+ licensing https://www.kegg.jp/kegg/legal.html)
- Reactome ContentService: https://reactome.org/ContentService/ ; AnalysisService:
  https://reactome.org/AnalysisService/ ; dev guide https://reactome.org/dev
- QuickGO API: https://www.ebi.ac.uk/QuickGO/api/index.html ; GO/geneontology API:
  https://api.geneontology.org/api/
- HPO API (current): https://ontology.jax.org/api/docs ; Monarch v3 API:
  https://api-v3.monarchinitiative.org/v3/docs
- MCP servers that already wrap these (reference designs): BioThings/MyGene &
  Monarch MCP, and the Reactome/KEGG community MCP tools — consider mirroring their
  endpoint choices.

---

## 6. Prioritized concrete fetcher improvements

**P0 — fix the two broken fetchers (both are small, high-impact):**
1. **HPO URL swap.** Replace `https://hpo.jax.org/api/hpo/search?q={q}&max=5&offset=0&category=terms`
   with `https://ontology.jax.org/api/hp/search?q={q}&limit=5`. Response already parses
   with existing `terms[].{id,name,definition}` mapping. Restores HPO from 0→working.
2. **GO text search → QuickGO.** Replace the broken
   `api.geneontology.org/api/search/entity/autocomplete/{q}?ontology=go` branch with
   `https://www.ebi.ac.uk/QuickGO/services/ontology/go/search?query={q}&limit=5`
   (header `Accept: application/json`), map `results[].{id,name}` → `{go_id,name}`. Keep
   the working `GO:\d+` → term-lookup branch (optionally also move it to QuickGO
   `ontology/go/terms/{id}` for consistent aspect/definition fields).

**P1 — add the resolution chains that make pathway queries actually useful:**
3. **KEGG gene→pathway.** When the query is a gene (symbol/Entrez), resolve via
   `conv/hsa/ncbi-geneid:{entrez}` (or `find/genes/{sym}+{org}`) then
   `link/pathway/{hsa:id}`, and `get`/`list` the pathway names. Swap `map`→`hsa` on the
   existing `find/pathway` branch for species-specific maps.
4. **Reactome gene→pathway + species filter.** Add `&species=Homo%20sapiens&cluster=true`
   to `search/query`; add a gene branch calling
   `data/mapping/UniProt/{acc}/pathways?species=9606`; strip `<span class="highlighting">`
   markup from `name`.
5. **HPO/Monarch phenotype→gene & →disease.** When query is `HP:\d+` (or resolved to one),
   call Monarch `v3/api/entity/{HP:id}/biolink:GeneToPhenotypicFeatureAssociation` for
   genes and `ontology.jax.org/api/network/annotation/{HP:id}` for diseases.

**P2 — enrichment context (systems-biology use case):**
6. **GO gene→annotation.** QuickGO `annotation/search?geneProductId=UniProtKB:{acc}&
   aspect=biological_process&limit=10`.
7. **Reactome AnalysisService.** POST a resolved gene-id list to
   `AnalysisService/identifiers/projection` for over-representation (p/FDR per pathway)
   — the enrichment-context use case Reactome is actually chosen for.
8. **KEGG pathway→genes.** `link/{org}/{pathway}` to expand a pathway into its gene set.

All P1/P2 need a gene-id resolution step (symbol → Entrez/UniProt), which the fan-out
already produces via the NCBI Gene / UniProt fetchers — thread those resolved ids into
KEGG/Reactome/GO rather than re-resolving.
