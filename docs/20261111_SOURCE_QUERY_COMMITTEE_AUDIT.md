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

---

## Round 2 (2026-11-12 overnight) — further audit/fix loops

A second committee pass (entity-extraction/routing + citation-retention surfaces) plus a
capability-gap closure. Commits `11952046a9` (BindingDB/Pharos) and `1b856103d1` (round-2
fixes). All on `feat/skills-architecture-20261111`, pushed, awaiting the shared deploy lane.

### Capability gap closed — BindingDB + Pharos fetchers (`11952046a9`)
Both were advertised in the facet maps but had surfaces `[single, mcp]` (no federation)
and no fetcher, so the honest-coverage gate correctly filtered them. Now wired:
- `_fetch_bindingdb`: resolve→UniProt → `getLigandsByUniprot`, surface the most POTENT
  measured affinities (Ki/Kd/IC50/EC50, nM). Handles the vendor typo key
  `getLindsByUniprotResponse`. Live: ABL1 → Kd 0.016 nM.
- `_fetch_pharos`: resolve→symbol → GraphQL target → development level (Tclin/Tchem/Tbio/
  Tdark) + family + novelty. Live: ABL1 → Tclin / Kinase.
- Added `SURFACE_FEDERATION` to both registry rows; registered in `_FETCHERS`; added to
  `ENTITY_SOURCES` (pharos→gene/protein, bindingdb→protein). 30 fetchers total.

### Round-2 fixes (`1b856103d1`)
| Sev | Defect | Fix |
|-----|--------|-----|
| HIGH | one slow entity's fan-out cancelled the WHOLE `gather` (single `wait_for(gather,20)`) → synthesis saw zero DB evidence | per-entity 15 s budget; slow entity times out alone, fast ones survive |
| MED-HIGH | `retrieval_stats.kept` computed BEFORE the existence check → the transparency panel reported citations later dropped from the answer | recompute from the lit pool that survived verification |
| MED | `_parse_json_array` anchored on the first `[` → a stray `[1]` citation shadowed the entity JSON, defeating the LLM-extraction path | scan every balanced `[...]`, prefer the array-of-objects |
| MED | dangling out-of-pool `[N]` (`[99]`/`[0]`) survived stage-1 grounding verbatim | strip unknown markers, matching stage-2 |
| MED | `refuse_without_evidence` deleted body prose ("Sources of bias" heading, "the DOI framework" sentence) | `_REF_HEAD`/`_ID_LINE` tightened to real bibliography headings + real id tokens |
| MED | `select_sources` safety inversion — empty serveable set (registry present-but-empty) skipped filtering like registry-unavailable | `_federation_serveable_ids` returns None (unavailable→pass through) vs set() (present→filter) |
| LOW | `"fold"` matched inside `"scaffold"` (genomics N50) | word-bounded `\bfold\b` |
| LOW | extraction prompt didn't order entities → with >3 entities an arbitrary subset grounded | prompt now asks to order by centrality (most important first) |

4 new regression tests (refuse-prose, fold/scaffold, prioriti scoping, registry pass-through).
55 agent + registry tests pass.

### Deferred (documented, NOT fixed — would be the keyword treadmill)
Ambiguous WHOLE-WORD facet cues (`domain`, `network`, `interaction`, `regulat`,
`constraint`) over-fire on biomedical-adjacent prose. Word-bounding does not help (they're
whole words); the right fix is an **LLM intent gate** in front of `detect_facets`, not more
keyword tweaks — aligns with the standing "infer solution-type, not keywords" direction.
Also deferred: `run_in_executor` cannot cancel the blocking thread on timeout (inherent;
per-entity budget bounds it); non-English questions get no facet routing (rule-based design).

---

## Dev-deployed + live-verified (2026-11-12, HEAD b88dda44e3)

Synced to dev via `scripts/sync_to_dev.sh` (result=healthy; workflow-gen + intent-driven
DB-search-routing smokes passed; ledger recorded b88dda44). Live `POST /api/ai_assistant/
research_query` on https://dev-public.biomate.ai:

- **PCSK9** (gene-constraint + disease-association) → the grounded answer QUOTES the exact
  values: *"gnomAD… PCSK9… pLI 2.765e-18 and a LOEUF of 1.1441346736692857"* and *"Open
  Targets identifies familial hypercholesterolemia… association score of 0.856."* The
  DB_GROUNDED_NOTICE fires; evidence boundary stated. This confirms the whole chain live:
  gnomAD facet selected (c680707650), OT+gnomAD rows survived the two-tier dedup, the
  grounding gate fired on substantive facts, and the directive made the model QUOTE the
  values instead of reverting to parametric hedging — the "famous entity → general
  knowledge" caveat is RESOLVED.
- **ABL1** (SAR/tractability/structure) → Pharos **Tclin** (new fetcher), UniProt **P00519**
  + PDB **1AB2** + AlphaFold (the F1 O/P/Q accession fix — P00519 structures now reachable),
  Open Targets CML association. A focused affinity query cites **BindingDB Kd 0.016 nM** for
  ABL1/P00519 with SMILES (new fetcher, live). The **anti-fabrication guard (#2) works**:
  when ChEMBL values were absent (EBI transiently flaky), the answer said so plainly instead
  of inventing IC50/Ki numbers.

### Minor follow-ups (not blockers)
- In a BROAD multi-source ABL1 query, BindingDB's affinity rows can be crowded out of the
  top-8 merged records fed to synthesis (round-robin + `merged[:8]` cap); a focused query
  surfaces them. Consider weighting bindingdb/chembl higher within the bioactivity facet
  merge, or raising the synthesis cap for bioactivity questions.
- ChEMBL/EBI intermittent 5xx (seen locally + on dev) — external reliability, not our code;
  the fetcher is correct and the failure is surfaced (not "ok, 0 results").

---

## Chat-path follow-up (read-only audit, 2026-11-12 — NOT yet fixed/verified)

The direct `/api/ai_assistant/research_query` endpoint is dev-verified (above). The
USER-FACING chat path wraps it via the `write_review` agentic tool
(`galaxy-assistant.ts:_toolWriteReview` → same endpoint → `scientificToolResult`). Traced
the DB-grounded (empty-citations) case:

- `scientificToolResult` (scientific-chat-tools.ts:90) tags an empty-citations answer
  `status: 'uncited'` with note *"No literature citations were returned. This is not a
  literature-backed review; disclose the source/fallback…"*.
- `galaxy-assistant.ts:5765` only adopts `citedResearch` (→ `groundedResearchReply`) when
  `status === 'ok'`, so a DB-grounded answer is NOT routed through the literature guard
  (good — it is not wrongly rejected). It is passed to the chat LLM as the tool result, and
  the LLM composes the final reply.

**Open question (needs empirical chat test, not yet run):** does the `'uncited'` status +
"this is not a literature-backed review" note cause the chat LLM to HEDGE a *database*-backed
answer (re-introducing, at the chat-composition layer, the "famous entity reverts to general
knowledge" behavior the research_agent fixes removed)? The answer text itself carries the
strong DB_GROUNDED_NOTICE, so net effect is unclear. Also: for a "what is PCSK9's LOEUF"
question the agent may route to `query_database` rather than `write_review`, in which case
this note never applies.

**Proposed (deferred, do carefully — sensitive replay-tuned guard):** give a DB-grounded
answer its own status (e.g. `'db_grounded'`) distinct from `'uncited'`, with a note that says
it IS a database-backed answer to be presented with its exact values — so the chat LLM
surfaces the gnomAD/Open Targets/BindingDB numbers confidently. Verify by driving
`/api/chat/stream` on dev with a PCSK9 question and checking the FINAL chat message quotes
LOEUF 1.144 + score 0.856 without hedging. Do NOT change the literature-citation guard
(`groundedResearchReply` line 37) — it correctly gates only `status === 'ok'` literature
answers.

### Chat-path follow-up — RESOLVED (empirically verified on dev, 2026-11-12)

Drove `/api/chat/stream` on dev with a DB-framed PCSK9 question ("What does gnomAD record
for PCSK9 loss-of-function constraint — the exact pLI and LOEUF values?"). Result:
`tool_events: ['research_query']` and the FINAL chat message presents the values
**confidently, no hedging**: *"pLI: 2.77 × 10⁻¹⁸ … LOEUF: 1.14 … Observed/Expected LoF ratio:
0.92"* with correct biology. So the `'uncited'`-status framing does NOT cause the chat LLM to
hedge a database-backed answer — the earlier concern was a false alarm. The user-facing chat
path surfaces the grounded-answer work correctly. **No chat-guard change needed.**

Secondary observation (OUT OF SCOPE — separate subsystem): a question phrased with "disease
association" + target framing routes the chat agent to the target-ranking tool
(`identify_targets` → target_id engine), which returned "AI-generated reasoning only, external
evidence not verified; Open Targets-primary ordering was not established." That is the
target_id/fuse_channels engine not contributing its Open Targets channel — unrelated to the
federated_query/research_agent source-query work; noted for whoever owns target ranking.

---

## Regression found post-deploy + fixed (2026-11-12, commit a90b240743)

After deploying the merge-priority fix (74f790b8), a BROAD ABL1 SAR query on dev returned
literature-only answers twice in a row — NO BindingDB/Pharos/PDB DB evidence at all (the
focused query still surfaced BindingDB Kd 0.016 nM). Root cause = a self-inflicted regression
from round-2:

- Round-2 replaced `wait_for(gather(all-entities), 20s)` with a per-entity
  `wait_for(federated_query, 15s)`. But `federated_query`'s OWN internal fan-out timeout is
  also **15s** (and on expiry it returns PARTIAL results — the sources that finished). The two
  15s timeouts TIE; when the asyncio wrapper won the race it cancelled `federated_query`
  before it could hand back its partials → `None` → the entity's entire DB evidence was lost.
  Intermittent (race-dependent), and worse for broad protein queries (~10 sources, a slow EBI/
  ChEMBL/BindingDB pushes the fan-out to the 15s edge).
- Fix: raise the per-entity wrapper to **25s** so `federated_query`'s internal 15s always
  fires first and returns its partials; the wrapper is now only a last-resort guard against a
  genuinely hung call. Entities run in parallel, so the larger budget adds no cross-entity
  wall-clock. (Also note: for the common SINGLE-entity query, round-2 had silently cut the
  budget 20s→15s; this restores comfortable headroom.)

Queued for the sync window after 74's. Verify post-sync: a broad ABL1 SAR query should
surface BindingDB/Pharos/PDB in the DB-grounded answer (not fall back to literature-only).
