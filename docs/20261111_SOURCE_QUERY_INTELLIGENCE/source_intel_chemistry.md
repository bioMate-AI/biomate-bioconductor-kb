# BioMate Source Intelligence — Chemistry / Drug-Discovery Cluster
Sources: ChEMBL, PubChem, ChEBI, BindingDB, SureChEMBL, Pharos
Audited 2026-11-11. All endpoints verified live with `curl -A "BioMate/1.0"`.

## Where the code lives (audited)
- Fan-out fetchers: `backend/lib/galaxy/ai/federated_query.py` — `_fetch_chembl` (L456), `_fetch_chebi` (L449), `_fetch_pubchem` (L483); registry `_FETCHERS` (L787). **No `_fetch_bindingdb`, `_fetch_pharos`, or `_fetch_surechembl` exist.**
- Single-source handlers: `backend/lib/galaxy/ai/ai_assistant.py` — `_query_bindingdb` (L7065), `_query_pharos` (L7112); dispatch map L7295. These are NOT reused by the fan-out.
- Source registry: `backend/lib/galaxy/ai/data_sources.py` — chebi/chembl/pubchem L86-92 (all 3 surfaces), **bindingdb L93 + pharos L95 = `SINGLE`+`MCP` only, NOT `FEDERATION`**; **surechembl = not registered at all**.
- Facet router: `backend/lib/galaxy/ai/evidence_source_router.py` — `bioactivity` → `[chembl, bindingdb, pubchem, chebi, pharos, uniprot, pdb]` (L44); `target` → `[pharos, opentargets, chembl, uniprot, string]` (L46). **The router names bindingdb/pharos, but the fan-out has no fetcher for them → silently dropped.**
- Skills: `skills/drug-discovery-chemist.md` (decision-tree/ADMET cutoffs, NO API detail), `skills/evidence-source-selection.md` (facet→source table, good conceptual map, no endpoints).

---

## 1. ChEMBL
**What:** EBI manually-curated bioactivity DB (IC50/Ki/Kd SAR, targets, mechanisms, drugs). Base `https://www.ebi.ac.uk/chembl/api/data/`. **Free, keyless.** JSON via `?format=json`.

**Right endpoint per entity type:**
| Entity | Endpoint |
|---|---|
| compound by name | `molecule/search?q=aspirin` |
| compound exact | `molecule?pref_name__iexact=IMATINIB` |
| **gene/target name** | `target/search?q=ABL1` → `target_chembl_id` |
| **activity/SAR** | `activity?target_chembl_id=CHEMBL1862&standard_type=IC50&pchembl_value__gte=6` |
| mechanism/MoA | `mechanism?target_chembl_id=CHEMBL1862` |
| structure search | `similarity/{SMILES}/{threshold}` or `substructure/{SMILES}` |

**Verified examples:**
- `target/search?q=ABL1&format=json&limit=3` → 17 hits; top is **CHEMBL3099 (Mus musculus)**, human ABL1 is **CHEMBL1862**. Returns `target_chembl_id`, `pref_name`, `organism`, `target_components[].accession` (UniProt P00519).
- `activity?target_chembl_id=CHEMBL1862&standard_type=IC50&pchembl_value__gte=6&only=molecule_chembl_id,standard_value,standard_units,pchembl_value,canonical_smiles&limit=1` → `{canonical_smiles, molecule_chembl_id:CHEMBL20867, pchembl_value:6.70, standard_units:nM, standard_value:200.0}` — clean SAR row.
- `mechanism?target_chembl_id=CHEMBL1862&limit=1` → `action_type:INHIBITOR, max_phase:4, mechanism_of_action:"Tyrosine-protein kinase ABL inhibitor"`.
- `similarity/CC(=O)Oc1ccccc1C(=O)O/80?format=json` → molecule list (structure→compound).

**Relevance filters that matter:** `pchembl_value__gte=6` (≥1µM, drops noise/inactives), `standard_type=IC50|Ki|Kd`, `assay_type=B` (binding), `target_organism=Homo sapiens`, `only=<fields>` (shrinks payload 10×), `limit`/`offset` pagination (default 20).

**Pitfalls:**
- `molecule/search?q=ABL1` returns **nothing** for a gene name — the classic category error. Must route gene/target → `target/search`.
- `target/search` returns mouse/rat orthologs ranked by score; **filter to `organism=Homo sapiens`** or you ground on the wrong species (CHEMBL3099 vs CHEMBL1862).
- target resolution alone (current fetcher) does NOT answer a SAR question — you still need the `activity` pull.
- Rate limit ~generous but be polite; use `only=` + `limit`.

**Current `_fetch_chembl` (L456) & GAPS:** molecule/search → on empty, falls back to target/search (good, added today for ABL1). **GAP: it stops at target annotation — never pulls the `activity` SAR table or `mechanism`.** For a potency/SAR query the user gets a target name but no IC50 numbers. No human-organism filter. No structure(similarity) path.

---

## 2. PubChem
**What:** NCBI compound DB (3D structure, properties, names, xrefs, patents, bioassay). Base `https://pubchem.ncbi.nlm.nih.gov/rest/pug/`. **Free, keyless.** Soft limit ≤5 req/s.

**Right endpoint per entity type:**
| Entity | Endpoint |
|---|---|
| compound by name | `compound/name/{name}/property/.../JSON` |
| compound by CID | `compound/cid/{cid}/property/.../JSON` |
| structure (SMILES) | `compound/smiles/{smiles}/cids/JSON` |
| name→SMILES | property list incl. `ConnectivitySMILES` |
| xref / patents | `compound/cid/{cid}/xrefs/PatentID/JSON` |

**Verified:** `compound/name/aspirin/property/IUPACName,MolecularFormula,MolecularWeight,ConnectivitySMILES/JSON` → `{CID:2244, MolecularFormula:C9H8O4, MolecularWeight:"180.16", ConnectivitySMILES:"CC(=O)OC1=CC=CC=C1C(=O)O", IUPACName:"2-acetyloxybenzoic acid"}`.

**Pitfalls:**
- PubChem **renamed `CanonicalSMILES`→`ConnectivitySMILES`** and `IsomericSMILES`→`SMILES` (2025). Current fetcher already handles both (`ConnectivitySMILES or CanonicalSMILES`) — good.
- Compound-only DB: a gene/target name returns nothing useful (correctly excluded by ENTITY_SOURCES compound-class).
- `MolecularWeight` is a **string**, not a number.

**Current `_fetch_pubchem` (L483) & GAPS:** name/cid property lookup, keyless, in fan-out. Solid. **Minor GAP:** no structure-search (`compound/smiles/{smiles}/cids`) and no patent xref path — but these overlap with ChEMBL/SureChEMBL duties; low priority.

---

## 3. ChEBI  ⚠️ BOTH CURRENT URLS ARE DEAD
**What:** EBI ontology of small molecules (role/structure classification, formula, mass, synonyms). **Free, keyless.**

**CURRENT FETCHER IS BROKEN — verified:**
- `_fetch_chebi` (L449) tries `https://www.ebi.ac.uk/chebi/searchId.do?chebiId=...` → **HTTP 301 → HTML** (dead legacy path).
- Fallback `https://www.ebi.ac.uk/webservices/chebi/2.0/lite?search=...` → **returns an HTML page, not JSON** (the old SOAP/REST service is retired). So `_fetch_chebi` returns `[]` for every query today.

**Working replacements (verified):**
- **New ChEBI backend ES search (preferred):** `https://www.ebi.ac.uk/chebi/backend/api/public/es_search/?term=glucose&size=5` → JSON `results[]._source` with `chebi_accession:"CHEBI:17234", name, ascii_name, formula:"C6H12O6", mass:180.156, monoisotopicmass, charge, stars, definition`. Exactly the fields a compound answer needs.
- **OLS4 (alternative):** `https://www.ebi.ac.uk/ols4/api/search?q=glucose&ontology=chebi&rows=5` → `response.docs[]` with `obo_id:"CHEBI:17234", label, description, synonyms, iri`.

**Pitfalls:** legacy `*.do` and `webservices/chebi/2.0` paths are retired — anyone citing them is wrong. The backend ES index name is date-stamped (`chebi-prod-compounds-11112026`) but the public ES-search alias is stable.

**GAP:** fetcher returns nothing for all inputs. Highest-ROI one-line swap in the cluster.

---

## 4. BindingDB  ⚠️ HANDLER USES A 404 ENDPOINT + NOT IN FAN-OUT
**What:** Measured binding affinities (Ki/Kd/IC50/EC50) target↔ligand with SMILES + PMID. Base `https://bindingdb.org/rest/`. **Free, keyless.**

**Right endpoint per entity type (verified):**
| Entity | Endpoint | Status |
|---|---|---|
| **target (UniProt)→ligands** | `getLigandsByUniprot?uniprot=P00519` (**singular**) | ✅ 200 |
| target (UniProt) plural | `getLigandsByUniprots?uniprot=...` | ❌ **404** |
| compound (SMILES)→targets | `getTargetByCompound?smiles={smiles}&cutoff=0.8` | ✅ 200 |

**Verified:** `getLigandsByUniprot?uniprot=P00519` → `{"getLindsByUniprotResponse":{"bdb.hit":"773","bdb.affinities":[{"bdb.monomerid":6866,"bdb.smile":"c1cc(...)","bdb.affinity_type":"Kd","bdb.affinity":" 68"},...]}}`. Note BindingDB's own typo'd key **`getLindsByUniprotResponse`** (no "ga"), fields prefixed `bdb.`.

**Pitfalls:**
- Query key is **UniProt accession**, not gene name — you must resolve ABL1→P00519 first (via UniProt or ChEMBL `target_components[].accession`).
- Plural/singular endpoint names and the response-key typo differ per endpoint — must hardcode exact strings.
- Responses can be 100s of KB/slow → needs ≥30s timeout.

**Current `_query_bindingdb` (ai_assistant.py L7065) & GAPS:**
- **BROKEN:** builds `getLigandsByUnipro**ts**` (plural, L7074) which **404s** → always `[]`. Must change to singular `getLigandsByUniprot`.
- Reads keys `a.get('query')/('monomerid')/('smile')/('affinity_type')/('affinity')` — but real singular response nests under `getLindsByUniprotResponse.bdb.affinities[]` with **`bdb.`-prefixed keys** (`bdb.smile`, `bdb.affinity_type`, `bdb.affinity`). Current key reads don't match → even if endpoint were right, mapping is wrong.
- **Not in fan-out** (`_FETCHERS`): a bioactivity fan-out never reaches BindingDB though the router lists it.

---

## 5. SureChEMBL  ⚠️ NO STABLE PUBLIC REST API
**What:** EBI patent-chemistry DB — compounds extracted from patent full text (structure→patent, patent→compounds). **Free.**

**Verified — there is no working JSON API:**
- `https://www.surechembl.org/api/`, `/api/chemistry/structure/{smiles}/0`, `/api/chemistry/similarity/{smiles}/90`, `/api/search/full_text/?q=` → **all 404**.
- `https://www.surechembl.org/search/?q=imatinib` → **200 but HTML** (UI only).
- **Bulk data exists:** `https://ftp.ebi.ac.uk/pub/databases/chembl/SureChEMBL/` → 200 (periodic patent-chemistry dumps, the real programmatic source).

**Correct architecture (matches today's dev finding):** SureChEMBL **free-text target search is pure noise** ("ABL1"→~95M junk). Its clean axis is **structure → patents**. With no live JSON API, the production path is:
1. ChEMBL `target/search?q=ABL1` → CHEMBL1862 → `activity?target_chembl_id=...&pchembl_value__gte=6` → active-compound SMILES/InChIKey.
2. Map those structures to patents via SureChEMBL **UI deep-link** (`surechembl.org/search/` by InChIKey) or the FTP bulk index — not a live fetcher.
Alternatively `ChEMBL document/search?q=ABL1` (verified 200) already returns patent+paper documents (`document_chembl_id`, journal/patent) for a target — a usable live patent-ish signal without SureChEMBL.

**GAP:** not registered in `data_sources.py`; no fetcher. **Recommendation: do NOT build a free-text SureChEMBL fetcher.** Register it as a structure/patent source whose live behavior routes through ChEMBL target→compound→document, and expose SureChEMBL only as a deep-link/bulk resource.

---

## 6. Pharos  ✅ HANDLER WORKS, BUT NOT IN FAN-OUT
**What:** NCATS target-illumination (TCRD) — target development level (Tclin/Tchem/Tbio/Tdark), family, novelty, ligand/drug counts. GraphQL at `https://pharos-api.ncats.io/graphql`. **Free, keyless.**

**Right use:** gene/target druggability & tractability (NOT compounds). POST GraphQL `{ target(q:{sym:"ABL1"}){ name tdl fam novelty ligandCounts{name value} } }`.

**Verified:** POST `{target(q:{sym:"ABL1"}){name tdl fam novelty}}` → `{"name":"Tyrosine-protein kinase ABL1","tdl":"Tclin","fam":"Kinase","novelty":0.00023803}`. Correct, live.

**Pitfalls:** query key is a **gene symbol** (`sym`), uppercase; wrong symbol → null. GraphQL POST only (no GET). It is a **target** source — don't send it a compound/SMILES.

**Current `_query_pharos` (L7112) & GAPS:** works for single-source. **GAP: not in `_FETCHERS`** → fan-out `target`/`bioactivity` facets never reach Pharos though the router lists it; also `data_sources` marks it `SINGLE`+`MCP` only (no `FEDERATION`).

---

## Existing docs/skills to integrate
**Repo (reuse):**
- `backend/lib/galaxy/ai/skills/evidence-source-selection.md` — facet→source table already correct (bioactivity → ChEMBL/BindingDB/PubChem/ChEBI/Pharos; target → Pharos/OpenTargets/ChEMBL). Good conceptual layer; just lacks endpoint recipes.
- `backend/lib/galaxy/ai/evidence_source_router.py` — facet routing already maps the sources; the fetchers just need to exist.
- `skills/drug-discovery-chemist.md` — decision cutoffs (IC50<1µM, hERG>30µM) for interpreting the SAR rows, not for querying.

**External (cite):**
- ChEMBL web-services: https://www.ebi.ac.uk/chembl/api/data/docs and https://chembl.gitbook.io/chembl-interface-documentation/web-services
- ChEBI (new API/OLS4): https://www.ebi.ac.uk/ols4/api and https://www.ebi.ac.uk/chebi/
- PubChem PUG-REST: https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest
- BindingDB REST: https://bindingdb.org/rwd/bind/BindingDBRESTfulAPI.jsp
- Pharos/TCRD GraphQL: https://pharos-api.ncats.io/graphql (schema at https://pharos.ncats.io/api)
- SureChEMBL bulk: https://ftp.ebi.ac.uk/pub/databases/chembl/SureChEMBL/ ; overview https://www.surechembl.org/
- Public MCP servers (Augmented-Nature, reference impls): PubChem-MCP, ChEMBL-MCP — mirror the endpoint shapes above.

---

## Prioritized, bounded fetcher improvements
**P0 — ChEBI fetcher (broken→working, 1-line swap).** In `_fetch_chebi` replace both dead URLs with `https://www.ebi.ac.uk/chebi/backend/api/public/es_search/?term={q}&size=5`; map `results[]._source` → `{chebi_id:chebi_accession, name, formula, mass, definition, stars}`. (Fallback OLS4 `ols4/api/search?q={q}&ontology=chebi&rows=5`.)

**P1 — ChEMBL SAR completion.** Extend `_fetch_chembl`: after resolving a target, filter `target/search` hits to `organism=="Homo sapiens"`, take `target_chembl_id`, then call `activity?target_chembl_id={id}&standard_type=IC50&pchembl_value__gte=6&only=molecule_chembl_id,canonical_smiles,standard_value,standard_units,pchembl_value&limit=10` and (optionally) `mechanism?target_chembl_id={id}`. Return the IC50/Ki SAR rows — the actual medchem answer, not just a target name.

**P2 — BindingDB: fix handler + add fan-out fetcher.** In `_query_bindingdb` change `getLigandsByUnipro**ts**` → `getLigandsByUniprot` (singular) and read `getLindsByUniprotResponse.bdb.affinities[]` with `bdb.smile`/`bdb.affinity_type`/`bdb.affinity`. Add `_fetch_bindingdb(q)` to `_FETCHERS` that resolves gene→UniProt (ChEMBL `target_components.accession` or UniProt) then calls the singular endpoint; register `bindingdb` with `SURFACE_FEDERATION` in `data_sources.py`.

**P3 — Pharos fan-out fetcher.** Add `_fetch_pharos(q)` to `_FETCHERS` wrapping the existing working GraphQL (`target(q:{sym}){name tdl fam novelty ligandCounts}`); add `SURFACE_FEDERATION` to the `pharos` registry row so the `target`/`bioactivity` fan-out reaches it.

**P4 — SureChEMBL: register as structure/patent route, no free-text fetcher.** Do NOT add a free-text `_fetch_surechembl` (404 API + noise). Register `surechembl` as a patent/structure source whose live retrieval is ChEMBL target→active-compounds→`document/search`, and expose SureChEMBL as a deep-link/bulk-FTP resource only.
