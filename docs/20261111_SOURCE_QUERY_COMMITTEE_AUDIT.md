# Source-Query / Grounded-Answer — Committee Audit & Fixes (2026-11-11)

Three independent adversarial reviewers audited this session's source-query /
grounded-answer work (the shared resolver, 8 fetcher rewrites, the merge/dedup,
stale-while-error, the synthesis/grounding path, and routing). Each read the
committed diffs and verified against live endpoints / scratch repros. This doc
records every finding, its disposition, and the verification.

Fix commit: `775d787b64` (branch `feat/skills-architecture-20261111`). Prior
gnomAD facet fix `c680707650` is pushed, held from deploy for session 08's lane.

## HIGH

| ID | Defect | Fix | Verified |
|----|--------|-----|----------|
| F1 | `_UNIPROT_ACC_RE = ^[A-NR-Z0-9][0-9][A-Z0-9]{3}[0-9]$` dropped the **O/P/Q** branch → silently rejected P04637 (TP53), P00519 (ABL1), P38398 (BRCA1) and every O/P/Q accession. A by-accession structure query then fell back to mygene (which `notfound`s accessions) and returned nothing — the exact structure-answer bug the rewrite meant to fix, still live for the most-studied proteins. (It worked in the ABL1 E2E only because that query resolved by *symbol*, so the regex was never exercised.) | Restored the official 6/10-char UniProt grammar: `^([OPQ][0-9][A-Z0-9]{3}[0-9]\|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2})$`. | Live: P04637/P00519 now match → direct AlphaFold path → 1 model each. Unit: 11/11 accession/non-accession cases. |
| M1 | Stale-while-error served the entire 30-day durable copy whenever `len(stale.merged) > len(fresh.merged)` — a **count-only** heuristic. One minor source blipping (an S2 429) discarded a fresh, authoritative fan-out (gnomAD/Open Targets) for an older snapshot, and the returned dict reported the old run's `sources_failed: []` while flagging `_stale`. | Narrow overlay: keep every fresh success, fill in the durable copy **only** for the sources that failed this run, report accurate `sources_succeeded` / `sources_failed` / `sources_stale`. | Reasoned + in-scope vars confirmed. |
| #1 | `_has_db_grounding` was true for **any** truthy db_fact (`elif _v:`), and `mygene_annotation` is set for any valid gene symbol → a pure identity lookup flipped `INSUFFICIENT_NOTICE` → `DB_GROUNDED_NOTICE`, falsely stamping a parametric answer "drawn from authoritative databases." | Exclude identity-only keys (`mygene_annotation`, `ensembl_genes`, `ensembl_gene_search`); grounding now rests on substantive facts (merged federated / ClinVar / Open Targets / GWAS / expression). Same exclusion applied to the confidence channel count (#4). | Test suite green. |

## MEDIUM

- **F2** — `resolve_gene` cached `{}` on a transient mygene 429/500, indistinguishable from "not a gene," poisoning the shared keystone for the TTL (every id-needing fetcher then read `{}` with no network call → reported "ok, 0 results"). Fix: `if r is None: return {}` without caching, so the next call retries.
- **F3** — A GraphQL `200 {errors:[...], data:null}` from gnomAD / Open Targets was never surfaced as a failure, so a future field rename would read as "the gene has no data." Fix: `_post_json` flags a non-empty `errors` body via `_note_failure`.
- **#3** — `if _llm_ents is not None:` treated an empty `[]` extraction as success, skipping the regex+mygene fallback (contra its own "never regress to zero DB evidence"). Fix: `if _llm_ents:`.
- **dedup M2/M3/M4** — the generic json dedup fallback truncated to 90 chars (over-merge → silent drop) and used bare `disease`/`partner`/`title[:60]` names as cross-source keys (mis-collapse of distinct evidence; "Part I/II" papers). Fix: two tiers — **stable id** (accession/pmid/doi/chembl/go/hpo/… ) → global key; **no id** → source-scoped FULL canonical content (no truncation). Keeps Open Targets/STRING score-rows (the original drop bug) while collapsing exact dup rows within a source. Validated against all six reviewer repros.
- **#2** — the db-facts directive carried literal example numbers ("1OPL at 3.42 Å", "score 0.86") — fabrication bait — and banned hedging unconditionally. Fix: describe *format* only; add an explicit "if the records do NOT contain the value, say so plainly rather than fill from memory" guard.
- **#5** — the generic federated-evidence render dropped any source whose value nests (`not isinstance(dict/list)`) → blank, re-introducing the "fetched but blank" bug. Fix: flatten one level (`key.subkey=val`; scalar lists join).

## LOW

- **F4** — `lookup_mygene` kept all hits for an ambiguous alias ("ABL" → ABL1/DSP-AS1/MTTP) → polluted annotations. Fix: keep top `_score` per input `query`.
- **F6** — the `"prioriti"` target-ranking cue fired the costly live orchestrator on generic text ("prioritize the samples"). Fix: scope to target/gene ranking phrases. (The `"constraint"`/`"intoleran"` variant cues are left as-is — low harm, gnomAD no-ops without a gene entity, and tightening with more keywords is the ad-hoc treadmill to avoid.)

## Verified CLEAN by the committee (no change needed)

Round-robin merge (empty/single/uneven-length), `src_order` construction, `json`
module-scope import, first-ever degraded query, no stale-flag leak into cache,
`citation_check` backward-compat; STRING/gnomAD/Open Targets/InterPro/ChEBI/HPO/
QuickGO/AlphaFold parse paths; mygene `r[0]` ordering; `_drop_mismatched_sources`;
cache-key-includes-source-set.

## Tests

- `test_evidence_source_router` updated to the honest-coverage gate: `bindingdb`/`pharos` are in the facet maps but have no federation fetcher, so `_federation_serveable_ids` correctly filters them (asserted present: chembl/pubchem/chebi/pdb; asserted filtered: bindingdb/pharos).
- Synthesis citation instruction strengthened to forbid inventing a **PDB ID** (not just DOI/PMID) — aligns with #2.
- Fixed **pre-existing** harness gaps (failed at HEAD, unmasked here): synthetic exec namespaces missing `_entity_validation_enabled`; `_synthesize_response` needing `_split_claims` + `_grounding_confidence`/`_validate_entity_claims` stubs; synthesis tests coupled to live PMID verification → added an autouse offline fixture.
- **51/51** agent + data-source-registry tests pass; `federated_query` + `evidence_source_router` import-check clean; `research_agent` py_compile clean (its heavy galaxy/scipy chain is covered via the AST-extract tests).

## Known gaps (tracked, not regressions)

1. **BindingDB / Pharos fetchers** — real SAR/affinity (BindingDB REST) and druggability (Pharos GraphQL) sources, advertised in the facet maps but not yet served by the fan-out. Adding fetchers is a genuine capability extension.
2. **M5** — round-robin lets rank dominate priority *across* ranks for a shared-id record (which source's field values win is data-dependent). Accepted: diversity > per-source priority for grounding; the commit's "priority breaks ties" holds only within a rank.
3. **M6/M7** — `:durable` cache suffix not namespace-isolated; `default=str` tuple→list type drift between fresh and cached returns. Cosmetic.

## Pending

Deploy `c680707650` (gnomAD facet) once session 08 releases the deploy lane, then
run the final PCSK9 E2E (expect Open Targets 0.856 + gnomAD LOEUF both cited). The
fixes in `775d787b64` ride the same sync.
