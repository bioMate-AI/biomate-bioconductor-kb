# Source Intelligence — STRUCTURE / PROTEIN cluster

Audit of how BioMate's federated query layer queries RCSB PDB, PDBe, AlphaFold DB,
InterPro, UniProt. Research + doc only (no source edits). All endpoints below were
VERIFIED live with `curl -A BioMate/1.0` on 2026-11-11.

Code audited:
- `backend/lib/galaxy/ai/federated_query.py` — `_fetch_uniprot` (L314), `_fetch_pdb`
  (L334), `_fetch_alphafold` (L359), `_fetch_interpro` (L503); `detect_entity_type`
  (L254); `ENTITY_SOURCES` (L144); `_FETCHERS` (L773).
- `backend/lib/galaxy/ai/data_sources.py` — registry L60–75.
- `backend/lib/galaxy/ai/skills/evidence-source-selection.md`,
  `backend/lib/galaxy/ai/skills/structural-biologist.md`.

---

## CROSS-CUTTING: the missing resolution spine

Every source in this cluster keys off a **UniProt accession** (e.g. `P00519`), yet
most real user queries arrive as a **gene symbol** (`ABL1`) or free text. There is NO
`gene → UniProt accession` resolver in `federated_query.py` (grep: only
`resolve_chemical_name` for compounds and the GEO `resolve_accession` MCP tool exist).
This single gap degrades AlphaFold (needs acc), PDBe `best_structures` (needs acc),
InterPro protein-mode (needs acc), and makes PDB fall back to weak full-text search.

**Verified resolution chain (the fix):**
```
gene_exact:ABL1 + organism_id:9606 + reviewed:true  → UniProt P00519 (ABL1_HUMAN)
P00519 → AlphaFold /api/prediction/P00519            → HTTP 200 model
P00519 → PDBe /mappings/best_structures/P00519       → 160 PDBs, ranked (top 1opl)
P00519 → InterPro /entry/interpro/protein/uniprot/P00519/ → domain set
```
Building this once (cached 24h) feeds all four downstream fetchers. This is the
highest-leverage change in the cluster.

---

## 1. UniProt

**1. What / base URL / auth.** Universal Protein Resource — sequences, function,
domains, xrefs, the canonical protein-ID hub. Base `https://rest.uniprot.org`.
Free, keyless, no account. Good for high volume.

**2. Key endpoints & which to use when.**
- `GET /uniprotkb/search?query=...` — the workhorse. Query syntax is field-scoped.
- `GET /uniprotkb/{accession}` — direct record when you already have an acc.
- `GET /uniprotkb/accessions?accessions=A,B` — batch fetch.
- `POST /idmapping/run` (From=Gene_Name/GeneID, To=UniProtKB) — bulk ID mapping.
- Entity routing:
  - **gene symbol** → `query=gene_exact:ABL1 AND organism_id:9606 AND reviewed:true`
  - **free text / protein name** → `query=<text> AND reviewed:true`
  - **UniProt acc** → `/uniprotkb/{acc}` directly
  - UniProt is also the hop that yields the acc for AlphaFold / PDBe / InterPro.

**3. Field constraints that improve relevance (VERIFIED).**
```
curl -A BioMate/1.0 \
 "https://rest.uniprot.org/uniprotkb/search?query=gene_exact:ABL1+AND+organism_id:9606+AND+reviewed:true&fields=accession,id,protein_name,gene_primary&size=2"
→ [{'acc':'P00519','id':'ABL1_HUMAN'}]   # exactly one canonical hit
```
Levers: `reviewed:true` (Swiss-Prot only, drops TrEMBL noise), `organism_id:9606`
(human; prevents ortholog spam), `gene_exact:` (exact symbol, not substring),
`fields=` (trim payload — big latency/size win vs full JSON), `format=json|list|tsv`.

**4. Pitfalls.** (a) Without `reviewed:true` you get hundreds of TrEMBL fragments.
(b) `gene:` does substring/fuzzy; `gene_exact:` is what you want for a symbol.
(c) No organism filter → mouse/rat orthologs rank alongside human.
(d) The default `recommendedName` path throws for entries that only have
`submissionNames` — current code already guards this.

**5. Current `_fetch_uniprot` + gaps.** Uses
`query={q} AND reviewed:true&size=5`. GAPS: (i) no `organism_id:9606` → ortholog
noise; (ii) no `gene_exact:` → a gene symbol is treated as free text, so `ABL1`
can rank below unrelated proteins whose text matches; (iii) no `fields=` → pulls
full records (slow); (iv) returns only name/function, **does not expose
`primaryAccession` as a resolution output for downstream fetchers** even though it
fetches it — the accession should be published to the fan-out so AlphaFold/PDBe/
InterPro can reuse it.

**6. Docs/skills.** External: UniProt REST docs
https://www.uniprot.org/help/api_queries , query fields
https://www.uniprot.org/help/query-fields , ID mapping
https://www.uniprot.org/help/id_mapping . Repo: `evidence-source-selection.md`
already lists UniProt for structure + target-biology questions.

**7. Prioritized fixes.**
1. Gene-symbol branch: when `detect_entity_type` says `gene`/all-caps token, query
   `gene_exact:{q} AND organism_id:9606 AND reviewed:true`; fall back to free-text
   if empty.
2. Add `fields=accession,id,protein_name,gene_primary,cc_function,xref_pdb` to cut
   payload and surface PDB xrefs for free.
3. Emit `primaryAccession` into a shared resolution context so AlphaFold/PDBe/
   InterPro fetchers consume it instead of re-detecting.

---

## 2. RCSB PDB

**1. What / base / auth.** Experimental 3D structures (X-ray, cryo-EM, NMR). Two
APIs: **Data API** `https://data.rcsb.org` (fetch by ID) and **Search API**
`https://search.rcsb.org/rcsbsearch/v2/query` (POST JSON). Free, keyless.

**2. Endpoints & routing.**
- `GET data.rcsb.org/rest/v1/core/entry/{PDB_ID}` — ONLY for a real 4-char PDB ID.
- `POST search.rcsb.org/rcsbsearch/v2/query` — text / sequence / attribute search.
  - **PDB ID** (`4HVP`, `1OPL`) → Data API entry.
  - **gene/protein text** → full_text search, OR better, go gene→UniProt acc and
    use attribute search on `rcsb_polymer_entity_container_identifiers.reference_sequence_identifiers`.
  - **raw sequence** → `service:"sequence"` (mmseqs2) with identity cutoff.

**3. Constraints / VERIFIED.** Valid-ID fetch:
```
curl .../core/entry/4HVP → title "...HIV-1 protease...", method X-RAY DIFFRACTION,
  resolution_combined [2.3]   (note: resolution is at rcsb_entry_info.resolution_combined,
  NOT reflns.d_resolution_high which is null for many entries)
```
Correct search pagination (VERIFIED):
```
POST search/v2/query  body:
 {"query":{"type":"terminal","service":"full_text","parameters":{"value":"ABL1 kinase"}},
  "return_type":"entry",
  "request_options":{"paginate":{"start":0,"rows":3},
                     "results_content_type":["experimental"]}}
→ total 4498, ids ['9F00','9F01','9KTJ']
```

**4. Pitfalls (confirmed live).**
- **ID misdetection:** `detect_entity_type` and `_fetch_pdb` flag ANY 4-alnum token
  as a PDB ID via `^[A-Za-z0-9]{4}$`. `ABL1` matches → `data.rcsb.org/.../entry/ABL1`
  → **HTTP 404 (verified)**. Real PDB IDs are `[1-9][A-Za-z0-9]{3}` — first char is a
  digit 1–9, never 0, and a bare `[A-Z]{4}` like a gene is never an ID.
- **`results_slice` is dead:** old v1 key → **HTTP 400 (verified)** on every text
  search. Must be `request_options.paginate{start,rows}`.
- Results unfiltered include computed models + CSMs unless
  `results_content_type:["experimental"]` is set.

**5. Current `_fetch_pdb` + gaps.** Already migrated to `paginate` (good; comment at
L348 documents the 400). GAPS: (i) ID regex `^[A-Za-z0-9]{4}$` still misfires on
gene symbols → 404 spam; must be `^[1-9][A-Za-z0-9]{3}$`. (ii) reads
`reflns.d_resolution_high` (often null) instead of
`rcsb_entry_info.resolution_combined[0]`. (iii) text-search path returns only bare
IDs (no title/method/resolution) — a second Data API hydrate per ID, or a GraphQL
batch, would make results usable. (iv) No `results_content_type` filter. (v) No
gene→acc→structure path (misses the precise reference-sequence attribute query).

**6. Docs/skills.** RCSB Search API https://search.rcsb.org/#search-api ,
Data API https://data.rcsb.org/redoc/ , query attributes
https://search.rcsb.org/structure-search-attributes.html . Public MCP:
`rcsb/py-rcsb-api` (rcsbapi Python package) is the official query builder — worth
vendoring its attribute constants. Repo `structural-biologist.md` covers
interpretation (resolution→interpretable features table) but not querying.

**7. Prioritized fixes.**
1. ID regex → `^[1-9][A-Za-z0-9]{3}$` in both `detect_entity_type` (L261) and
   `_fetch_pdb` (L336). Kills the 404 class.
2. Resolution field → `rcsb_entry_info.resolution_combined[0]`.
3. Hydrate text-search IDs with one Data API / GraphQL batch (title, method,
   resolution) so the card isn't just an ID list.
4. Add `"results_content_type":["experimental"]`.

---

## 3. PDBe

**1. What / base / auth.** EBI's PDB mirror + rich derived/aggregation APIs (SIFTS
UniProt↔PDB mappings, best-structure ranking, validation, ligands). Base
`https://www.ebi.ac.uk/pdbe/api`. Free, keyless.

**2. Endpoints & routing.**
- `GET /pdb/entry/summary/{id}` — entry metadata (alt to RCSB Data API).
- `GET /mappings/best_structures/{UNIPROT_ACC}` — **killer endpoint**: returns PDB
  structures for a protein, pre-ranked by coverage/resolution. Ideal acc→structure.
- `GET /mappings/uniprot/{id}` — SIFTS residue-level UniProt↔PDB mapping.
- Routing: **UniProt acc** → `best_structures` (ranked list); **PDB ID** → summary.

**3. Constraints / VERIFIED.**
```
curl .../pdbe/api/pdb/entry/summary/4hvp → title + experimental_method ['X-ray diffraction']
curl .../pdbe/api/mappings/best_structures/P00519
  → 160 structures, ranked; top pdb_id 1opl, resolution 3.42
```
`best_structures` already sorts best-first (coverage then resolution), so taking the
first N gives the most useful structures for a target with zero extra logic.

**4. Pitfalls.** (a) PDB IDs must be **lowercase** in PDBe URLs (`4hvp`, not `4HVP`).
(b) Response is keyed by the (lowercased) query id → must index `d["<id>"]`, not a
`results` array. (c) `best_structures` needs an accession, not a gene.

**5. Current fetcher + gaps.** **PDBe is registered in `data_sources.py` (L70) but
has NO `_fetch_pdbe` and is absent from `_FETCHERS`** → it is listed as a capability
but is dead in federation (only `SURFACE_SINGLE, SURFACE_MCP` surfaces, so federation
never reaches it). The single most impactful aggregation endpoint for "what
structures exist for my target" (`best_structures`) is entirely unused.

**6. Docs/skills.** PDBe REST docs https://www.ebi.ac.uk/pdbe/api/doc/ ,
SIFTS https://www.ebi.ac.uk/pdbe/docs/sifts/ , PDBe-KB
https://www.ebi.ac.uk/pdbe/pdbe-kb/ . `evidence-source-selection.md` lists PDBe for
structure questions but there's no fetcher behind it.

**7. Prioritized fixes.**
1. Add `_fetch_pdbe`: if acc present → `/mappings/best_structures/{acc}` (ranked
   PDBs with resolution + coverage); elif PDB ID → `/pdb/entry/summary/{id.lower()}`.
2. Register it in `_FETCHERS` and add `SURFACE_FEDERATION` to the registry so the
   fan-out actually calls it.
3. Use `best_structures` as the acc→structure resolver for the `structure` entity
   type (more informative, pre-ranked, than RCSB full-text).

---

## 4. AlphaFold DB

**1. What / base / auth.** EBI/DeepMind predicted structures for UniProt sequences
(~214M models). Base `https://alphafold.ebi.ac.uk/api`. Free, keyless.

**2. Endpoints & routing.**
- `GET /api/prediction/{UNIPROT_ACC}` — the only query path; returns model URLs
  (`pdbUrl`, `cifUrl`), `paeImageUrl`, versioning. **Requires a UniProt accession.**
- Entity routing: **UniProt acc** → direct. **gene symbol / text / PDB ID** → must
  resolve to acc via UniProt first (no name search exists).

**3. Constraints / VERIFIED.**
```
curl .../api/prediction/P00519 → HTTP 200, full model payload (pdbUrl, paeImageUrl…)
```

**4. Pitfalls.** (a) No gene/text search — a bare symbol returns nothing without the
UniProt hop. (b) Only one model per canonical accession; isoforms often absent.
(c) Confidence is per-residue pLDDT in the model file, not a single scalar in the API
(the current `"confidence":"pLDDT"` string is a placeholder, not a value).

**5. Current `_fetch_alphafold` + gaps.** Correctly requires an acc and returns a
clear note when absent. GAP: the note is the END of the line — it never triggers the
gene→UniProt resolution, so for the common `ABL1`/free-text case it always returns
empty. Wiring the shared resolver (resolve acc, then call `/prediction/{acc}`) makes
AlphaFold productive for gene-symbol queries.

**6. Docs/skills.** AlphaFold API https://alphafold.ebi.ac.uk/api-docs ,
FAQ https://alphafold.ebi.ac.uk/faq . `structural-biologist.md` has strong pLDDT/PAE
interpretation guidance (>90 confident, 70–90 moderate, <50 disordered) — good to
surface alongside the model link.

**7. Prioritized fixes.**
1. Consume the shared UniProt accession: `gene → acc → /prediction/{acc}`.
2. Return `cifUrl` + `latestVersion` and, if cheap, parse mean pLDDT from the model
   for an at-a-glance confidence number.

---

## 5. InterPro

**1. What / base / auth.** Protein families, domains, functional sites (integrates
Pfam, CATH-Gene3D, PANTHER, CDD, PROSITE, SMART…). Base
`https://www.ebi.ac.uk/interpro/api`. Free, keyless.

**2. Endpoints & routing.**
- `GET /entry/interpro?search={text}` — **curated InterPro entries** by text.
- `GET /entry/all/?search={text}` — InterPro + all member-DB entries (broader).
- `GET /entry/interpro/{IPRxxxxxx}` — direct accession lookup.
- `GET /entry/interpro/protein/uniprot/{acc}/` — **domains on a given protein**.
- Routing: **free text / family name** → `/entry/interpro?search=`; **IPR accession**
  → direct; **UniProt acc** (to annotate a target's domains) → `/entry/interpro/
  protein/uniprot/{acc}/`.

**3. Constraints / VERIFIED.**
```
curl ".../api/entry/interpro?search=kinase&page_size=3"
  → count 1149, ['IPR000023','IPR000239','IPR000333']
curl ".../api/entry/all/?search=kinase&page_size=3"
  → count 4304, ['cd00012','cd00029','cd00075']   (incl. member-DB)
curl ".../api/entry/interpro/IPR000719"
  → name "Protein kinase domain", type "domain"
curl ".../api/entry/interpro/protein/uniprot/P00519/" → HTTP 200 (domain set)
```

**4. Pitfalls (confirmed live — this fetcher is BROKEN).** The endpoint the current
code hits, `/entry/?search=kinase`, does **not** return a `results` list at all — it
returns a database-count summary object:
```
curl ".../api/entry/?search=kinase" → {"entries":{"member_databases":{"pfam":53233,…},
  "integrated":87956,"unintegrated":41833,…}}   # NO results[] key
```
So `(data or {}).get("results", [])` is `[]` **for every query** → InterPro always
returns zero. The `/entry/` path is a counts/overview endpoint, not a search result
set. Correct is `/entry/interpro?search=` (or `/entry/all/?search=`). Also note
pagination is `page_size` + `page` (NOT `paginate`/`rows`).

**5. Current `_fetch_interpro` + gaps.** `/entry/?search={q}&page_size=5` → silently
empty always (the headline bug). GAP: wrong endpoint; no protein-mode (`.../protein/
uniprot/{acc}/`) to annotate a target's domains from its accession; no accession
direct-lookup branch.

**6. Docs/skills.** InterPro API docs https://www.ebi.ac.uk/interpro/api/static_files/
(interactive) and https://interpro-documentation.readthedocs.io/ ; Pfam is now served
via InterPro. `evidence-source-selection.md` lists InterPro for structure/domain Qs.

**7. Prioritized fixes.**
1. Change endpoint to `/entry/interpro?search={q}&page_size=5` (fixes the
   always-empty bug). Fields: `metadata.accession/name/type/source_database`.
2. Add accession branch: `^IPR\d{6}$` → `/entry/interpro/{acc}`.
3. Add protein-annotation mode: when a UniProt acc is in context, call
   `/entry/interpro/protein/uniprot/{acc}/` to list the target's domains/families.

---

## Appendix — verified curl matrix (2026-11-11, `-A BioMate/1.0`)

| # | Call | Result |
|---|------|--------|
| PDB entry (valid) | `data/.../entry/4HVP` | 200, HIV-1 protease, X-RAY, 2.3Å |
| PDB entry (gene) | `data/.../entry/ABL1` | **404** (ID misdetection) |
| PDB search old | `paginate→results_slice` | **400** (dead param) |
| PDB search new | `request_options.paginate` | 200, total 4498, ids 9F00… |
| UniProt gene | `gene_exact:ABL1+organism_id:9606+reviewed:true` | P00519 / ABL1_HUMAN |
| AlphaFold | `/api/prediction/P00519` | 200, model payload |
| PDBe summary | `/pdb/entry/summary/4hvp` | 200, X-ray diffraction |
| PDBe best_structures | `/mappings/best_structures/P00519` | 160 PDBs, top 1opl@3.42Å |
| InterPro (current) | `/entry/?search=kinase` | counts object, **no results[]** |
| InterPro (fixed) | `/entry/interpro?search=kinase` | count 1149, IPR000023… |
| InterPro protein | `/entry/interpro/protein/uniprot/P00519/` | 200, domain set |
| InterPro acc | `/entry/interpro/IPR000719` | "Protein kinase domain", domain |
