# Source Query Intelligence & Grounded Answers — 2026-11-12

A session's worth of work making BioMate's grounded-answer path draw on the *right*
records from its external databases and cite them as first-class evidence. Everything
below was curl-verified against the live APIs and deployed + E2E-verified on dev
(`dev-public.biomate.ai`). Branch: `feat/skills-architecture-20261111`.

Companion artifacts:
- Skill: `backend/lib/galaxy/ai/skills/source-query-intelligence.md` (LLM-facing recipes).
- Per-cluster audits: `docs/20261111_SOURCE_QUERY_INTELLIGENCE/source_intel_*.md`.
- Earlier evidence-pipeline work: `docs/20261111_EVIDENCE_PIPELINE_AND_UI_SESSION.md`.

---

## 1. The problem

The research/grounded-answer path (`research_agent._gather_evidence` →
`federated_query`) queried external DBs naively: one entity → one endpoint, by a coarse
`detect_entity_type`. Three failure classes resulted:

1. **Broken fetchers** — several sources hit dead/retired/wrong endpoints and returned
   empty or garbage in production, silently.
2. **No identifier resolution** — most sources reject a bare gene symbol (AlphaFold/PDBe
   need a UniProt accession, gnomAD/Open Targets need an ENSG, KEGG an Entrez id), so a
   question about "ABL1" reached none of them.
3. **DB facts discarded at synthesis** — even when data was fetched, the literature-biased
   synthesis prompt dropped it (field-name mismatch in rendering; "unreferenced
   background" framing; an over-broad "never invent an identifier" rule).

Net symptom: "What structures exist for ABL1?" → *"specific identifiers cannot be
provided."* (Data was there; the pipeline threw it away.)

---

## 2. Per-DB audit → the source-query-intelligence skill

Six parallel research agents audited every federated source (chemistry, structure,
gene, pathway, variant, literature), curl-verifying each endpoint. Output:
`docs/20261111_SOURCE_QUERY_INTELLIGENCE/source_intel_*.md` (full) and the distilled
LLM skill `backend/lib/galaxy/ai/skills/source-query-intelligence.md` (use-case →
endpoint recipes, resolve-then-route principle, pitfalls). Companion to
`evidence-source-selection.md` (which picks *which* sources; this says *how* to query
each well).

**Core principle: resolve, then route.** A target like `ABL1` is first resolved to the
identifier each source consumes, then the use-case-specific endpoint is called.

---

## 3. Eight broken/degraded fetchers repaired (`628816e386`)

All in `backend/lib/galaxy/ai/federated_query.py` (+ `research_agent.lookup_mygene`),
each curl-verified, deployed, E2E-confirmed:

| Source | Was (prod) | Fix |
|---|---|---|
| HPO | `hpo.jax.org/api/hpo/search` serves SPA HTML → 0 results every call | → `ontology.jax.org/api/hp/search` (same `terms[]` shape) |
| GO | `api.geneontology.org` autocomplete → non-human gene products + hex-blob ids | → QuickGO `/QuickGO/services/ontology/go/search` (clean `GO:` terms) |
| InterPro | `/entry/?search=` → DB-counts summary, no `results[]` → always empty | → `/entry/interpro?search=` |
| ChEBI | `searchId.do` / `webservices/chebi/2.0/lite` retired → `[]` every call | → `/chebi/backend/api/public/es_search/` |
| STRING | only `get_string_ids` (no partners, `score` always None) | → `interaction_partners?...required_score=700` |
| mygene | `q=symbol:` only → `p53`/`BCR-ABL`/`HER2`/`CD20` → 0 | → batch POST `/v3/query` `scopes=symbol,alias,retired` |
| Crossref | no `mailto` → 1 req/s public pool | → `&mailto=` (3 req/s) + `query.bibliographic` |
| OpenAlex | `mailto` only in UA, not the query param | → `&mailto=` query param |

E2E (TP53): answer returned real InterPro domains + STRING interaction partners — both
were empty before.

---

## 4. The keystone: a shared identifier resolver (`5e694c3405`, `ea1545f818`)

`federated_query.resolve_gene(symbol)` — one cached, alias-safe mygene call →
`{symbol, entrez, ensembl, uniprot}` (ABL1 → 25 / ENSG00000097007 / P00519; p53 → TP53;
BCR-ABL → ABL1). 24h Redis cache; shared by every id-needing fetcher.

Consumers wired through it (all curl-verified live):
- **AlphaFold** — resolve → UniProt → `/prediction/{acc}` (returned nothing for a bare
  symbol before).
- **PDBe** (NEW `_fetch_pdbe`) — resolve → UniProt → `best_structures` (ranked
  experimental PDBs; ABL1 → `1opl`@3.42 A). Registered in `_FETCHERS`,
  `ENTITY_SOURCES[protein/structure]`, + `SURFACE_FEDERATION`. Endpoint was unused.
- **RCSB PDB** — resolve → UniProt → search by
  `reference_sequence_identifiers.database_accession` (the old full-text search returned
  `9F00`/`9KTJ` noise — newest entries matching the string, not ABL1 structures).
- **ChEMBL activity** — target/search → human `target_chembl_id` →
  `activity?standard_type=IC50&pchembl_value__isnull=false&order_by=-pchembl_value` →
  ABL1 top IC50 **0.015 nM / pChEMBL 10.82**.
- **gnomAD** (rewritten) — resolve → ENSG → `gnomad_constraint` (pLI, LOEUF, oe_lof,
  missense-z; PCSK9 LOEUF 1.144). The old generic `search` returned only an id.
- **Open Targets** (NEW `_fetch_opentargets`) — resolve → ENSG → `associatedDiseases`
  (scored; PCSK9 → familial hypercholesterolemia 0.856). Registered + `SURFACE_FEDERATION`
  (it had a dedicated target-id channel but no fan-out fetcher).

---

## 5. Making DB facts reach, and be cited by, the synthesis

The data was fetched but discarded at three points — all fixed:

1. **Merge buried structure/activity records** (`6eb0c398d1`). `_merge_results` drained
   per-source in priority order, so a gene-typed target's identity sources (uniprot,
   ncbi_gene) filled the prompt's top-8 and pushed `pdb`/`pdbe`/`alphafold`/`chembl`
   past the cap. Fixed with a **round-robin** merge (every source's top result first).
2. **Rendering dropped non-literature fields** (`7fdbae3b60`). The federated-evidence
   prompt rendering only read `name`/`title`/`summary`, so PDBe (`pdb_id`/`resolution`),
   STRING (`partner`/`score`), ChEMBL (`chembl_target_id`) rendered as blank bullets.
   Fixed with a generic field fallback.
3. **Literature-only framing discarded DB grounding** (`7fdbae3b60`, `f68f8a2d4b`,
   `562f7aafee`). `citation_check` tagged any answer with no grounded *literature* as
   "unreferenced background". Added `DB_GROUNDED_NOTICE` + a `db_grounded` flag from
   `research_agent`. Then the synthesis prompt's "never invent a PDB ID" rule (meant for
   literature) made the LLM refuse to cite the *real* PDB IDs in db_facts, and the
   "EVIDENCE: insufficient" verdict was literature-only — both scoped/fixed. Finally the
   db-facts directive was broadened to cover every value type (PDB+resolution,
   accessions, ChEMBL IC50/pChEMBL, Open Targets disease+score, gnomAD pLI/LOEUF, ClinVar
   significance, STRING partner+score) and to forbid the "widely known" / "unreferenced
   background" / "cannot be provided" hedges when a record supplies the value.

**E2E proof:** "List PDB structures for ABL1" → answer cites **`1OPL`@3.42 A, 1AB2,
1AWO** + UniProt P00519 + AlphaFold model (was "specific identifiers cannot be
provided").

**Known caveat (LLM-behavioral, not data):** citation of specific values is reliable for
distinctive records (PDB IDs) but for very famous genes (PCSK9) the LLM can still
paraphrase from parametric knowledge; the `562f7aafee` directive targets this and is the
current lever. Every consumer returns correct data on-box regardless.

---

## 6. LLM entity extraction (retired regex) + Semantic Scholar disable

- **Entity extraction** (`4d52ee8cfc`): the hot path now asks the LLM for the entities a
  question is *about* with their types (gene/compound/variant/…), excluding analysis
  acronyms (SAR/PK/ADMET). The regex typer (`detect_entity_type`, gene-symbol regex) no
  longer touches routing — the resolved type flows into `federated_query(entity_type=…)`.
  Founder feedback drove this ("as an LLM, you love regex?"). Verified: fan-out entity
  list went `['SAR','ABL1']` → `['ABL1']`.
- **Semantic Scholar** (`4214c210b5`, `e944c6ddf3`): keyless it 429s on nearly every
  call; gated OFF in all three answer-path call sites (literature client, federated
  fetcher, `_fetch_s2_paper` enrichment), keyed on `SEMANTIC_SCHOLAR_API_KEY`. The live
  E2E caught the third path after the first two were gated — exactly why only E2E counts.

---

## 7. Skill-loading architecture (wired)

Two loaders exist: `SkillManager` (`skill_manager.py`, loads
`backend/lib/galaxy/ai/skills/*.md` by YAML `triggers`/`domains`) — wired into the CHAT
path via `galaxy-assistant.ts` → `/api/skills/detect` → `/api/skills/block`; and
`SkillLoader` (`skill_loader.py` → `/app/skills` SKILL.md tree, hardcoded
`INTENT_TO_SKILLS`) — used by the research path. Fixes (`2f14ed77de`):
`source-query-intelligence.md` had no frontmatter so SkillManager loaded it with zero
triggers (inert) — added it (verified `/api/skills/detect` → the skill); and the
grounded-answer path now also injects SkillManager's trigger-matched expert skills.

---

## 8. Fast queries for large DBs

- **Internal catalog** (`galaxy_ai_tools.db`, 12k tools): already fast — `VectorToolSearch`
  with sentence-transformer embeddings in a DB-native `tools.embedding` BLOB, warm
  in-memory, shared `embed_server`. (Weakness is coverage — ~10k tools lack
  `scientific_context_v2` — not speed.)
- **External DBs**: live REST + Redis cache (24h stable / 1h literature) + parallel
  fan-out. **Tier 1 built — stale-while-error** (`3a1902f32b`): federated_query keeps a
  30-day last-known-good and serves it (flagged `_stale`) when live sources fail, so the
  EBI/NCBI/Semantic-Scholar outages hit this session no longer return empty.
- **Not built (deliberate):** tier 2 (durable disk cache) is redundant — dev Redis is
  external ElastiCache, so tier 1 already survives restarts; tier 3 (full ChEMBL/UniProt
  SQLite mirrors) is a GB data-hosting ops task — the offline-resolver scaffold
  (`local_compound_resolver.py`, `local_literature.py`, `set_local_resolver`,
  `BIOMATE_OFFLINE_MODE`) is ready, it needs the data hosted + cloud-mode mirror-first
  wiring.

---

## 9. Deploy-ops lesson: the orphaned lease

`sync_to_dev.sh` acquires a remote lease via `mkdir /opt/biomate/.dev-deploy.lock` and
releases it only in an `on_exit` trap; a sync killed before the trap (too-short
background timeout, or session teardown) orphaned it and **blocked all deploys**, with
no staleness break. Added one (`236ba8d941`): the lease self-heals when older than 30 min
(double any real sync) with no live sync running — never touches a live deploy. Always
run a sync with a FULL background timeout (≥1800000 ms). The deploy itself usually
*completed* before the kill — check build-info/container before assuming failure. A
backend-only change does not move frontend `build-info.json`; verify by greping the
galaxy container.

---

## 10. Status & open items

**Live + verified on dev:** all 8 fetcher repairs; the shared resolver + AlphaFold/PDBe/
RCSB-by-UniProt/ChEMBL-activity/gnomAD/Open-Targets consumers; the merge/rendering/
framing/directive fixes (ABL1 structures cited end-to-end); the source-query-intelligence
skill (loaded + detected); stale-while-error; the lease staleness-break; LLM entity
extraction; Semantic Scholar gated.

**Open / roadmap:**
- Synthesis-consistency for famous entities — directive `562f7aafee` is the current
  lever; if still inconsistent, a deterministic post-synthesis value-injection.
- Free API keys (both wired to env): `SEMANTIC_SCHOLAR_API_KEY`, `NCBI_API_KEY` — raise
  limits, re-enable S2.
- Tier-3 local mirrors (ops/data decision); tool `scientific_context_v2` enrichment
  (~10k tools) for better vector-search coverage.
- Patents: `SureChEMBL` free-text is noise; the clean path is ChEMBL target → active
  compounds → SureChEMBL structure search → patents (not yet built).
