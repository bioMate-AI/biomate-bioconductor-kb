# Parallelism + Chaining — Worktree Implementation Notes (C7 + C2 prototype)

**Companion to**: `docs/20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md`
**Branch**: `worktree-agent-aaf4e393b5ea5b614`
**Status**: green tests, not merged. Awaiting review.

## What shipped

### C7 — chain-hint fallback drift guard

Discovery during implementation: **`_getChainHintNames()` already fetches chain names dynamically from `/api/workflow-chains?intent_hint=true`** with a 10-min cache (`frontend/server/galaxy-assistant.ts:3597`). The original drift concern from `docs/20260509_BIOMATE_MULTI_WORKFLOW_PLANNING_ARCHITECTURE.md` §4.2 is mitigated for the happy path.

The real drift risk that remained: the **hardcoded fallback list** used when Galaxy is unreachable at boot. It contained 8 chains; the DB has 29 intent-eligible chains. Boot-time fallback was silently dropping 21 chains from classifier coverage.

Changes:
- New module `frontend/server/chain-hint-fallback.ts` exporting `CHAIN_HINT_FALLBACK: readonly string[]` (29 entries, alphabetical, matches DB).
- `galaxy-assistant.ts` imports the constant; removed inline 8-entry list.
- `frontend/server/__tests__/chain-hint-fallback.test.ts` — 5 vitest guards:
  1. Load-bearing chain names present (`bulk_rnaseq_de_analysis`, `target_to_lead_full`, `pbpk_to_tumor_tgi`, etc.).
  2. No duplicates.
  3. Size ≥ 20 (catches accidental truncation).
  4. Identifier-style names only (no whitespace / slashes).
  5. Sorted case-insensitively for diff readability.

Why a standalone module: importing the constant from `galaxy-assistant.ts` would transitively pull in `server/db.ts` and fail at test load time (DATABASE_URL gate). Two test files in the suite already fail this way — a pre-existing condition unrelated to this change.

### C2 — typed-port chain planner prototype

New module `backend/lib/galaxy/ai/chain_planner.py` (216 LOC).

- `plan_chains(start_input_types, goal=None, goal_output_types=None, max_steps=4, top_k=3, db_path=None) -> list[PlannedChain]`.
- BFS over a workflow-level edge graph. Edge A→B exists iff any of A's `output_types` satisfies any of B's `input_types` under the alias table.
- Reuses `_TYPE_ALIASES` from `workflow_chain.py` via lazy import (with a conservative built-in copy for standalone use). Single source of truth preserved.
- Scoring: base = `10/len(steps)` (shorter wins ties), domain coherence bonus (+0.5 when ≤2 distinct domains), goal-keyword bonus (+1.0 when keyword appears in step name/description).
- CLI: `python -m galaxy.ai.chain_planner --start fastq --goal "enrichment" --top-k 3`.

Tests: `backend/tests/test_chain_planner.py` — 7 pytest cases using an in-memory style temp SQLite fixture (no dependence on the 3,094-row catalog):
1. Three-step linear chain found end-to-end.
2. `max_steps` is respected.
3. Impossible goal returns `[]`.
4. Empty start types returns `[]`.
5. No duplicate plans emitted via alternate alias paths.
6. Score prefers shorter chains on ties.
7. Connections record the bridge types between adjacent steps.

## Test results

| Suite | Result |
|---|---|
| `backend/tests/test_chain_planner.py` | **7 passed** |
| `frontend/server/__tests__/chain-hint-fallback.test.ts` | **5 passed** |
| Full frontend `vitest run` | **564 passed, 4 skipped**; 2 unrelated test files still fail (DATABASE_URL not set in env — pre-existing, confirmed by running on stashed working tree) |
| `tsc --noEmit -p .` | 1 pre-existing error (`RollIntoIndAffordance` missing — visible in initial `git status`); zero new errors |

## Quality fixes applied after first-pass smoke (commit 2)

The first-pass smoke surfaced three real bugs in the planner. All fixed in the second commit; see new tests in `test_chain_planner.py`.

| Bug | Cause | Fix |
|---|---|---|
| 1-step shortcut: fastq → differentialabundance | `_TYPE_ALIASES["fastq"]` includes `"samplesheet"` (production needs this to validate nf-core curated chains where a samplesheet *describes* fastqs). The prototype's BFS turned that into a transitive equivalence. | Local-to-planner blocklist `_PLANNER_ALIAS_BLOCKLIST` strips the wrong-direction aliases (`fastq→samplesheet`, `*→input`, `counts_matrix→samplesheet`, etc.). Production `_TYPE_ALIASES` untouched. |
| Loose substring matching | `_type_satisfies` did `in_type in alias or alias in in_type`. This matched things like `"fastq"` ⊂ `"input_fastq_dir"`. | Now strict: equality or explicit alias-table membership only. |
| Junk plans from drug-discovery / nf-core workflows | Indexer at `backend/scripts/index_all_workflows.py:309` (`extract_biomni_input_output`) writes `params.*` names as `input_types` for biomni Nextflow workflows. Many nf-core entries have `input_types=["input"]` placeholder. | `_is_meaningful_input_types` rejects workflows whose `input_types` is the placeholder OR ≥50% strings that look like param names (`_mode`, `_file`, `max_*`, `min_*`, `mock_mode`, `gpu`, etc.). These workflows are skipped at load time. The underlying indexer bug should be fixed separately. |

### Smoke results after fixes (same 4 queries)

| Query | Before | After |
|---|---|---|
| `--start fastq --goal-types gsea_results enrichment_results` | 1-step shortcut to differentialabundance | 2-step **nf-core/rnaseq → nf-core/differentialabundance** (canonical) and **nf-core/scrnaseq → nf-core/differentialabundance** |
| `--start vcf --goal "annotation"` | `nf-core/isoseq`, `nf-core/phageannotator` (all with `input_types=["input"]`) | Real variant-calling tools with `vcf`-typed inputs. (Top-1 imputation, not annotation — a separate catalog-completeness issue, not a planner bug.) |
| `--start smiles --goal "ADMET"` | Workflows with param-name `input_types` (`max_routes`, `pass_max_steps`, ...) | `aizynthfinder_retrosynthesis`, `cns_penetration_prediction`, `covalent_warhead_design` — all with clean `input_types=["smiles"]` |
| `--start counts_matrix --goal "enrichment"` | Correct 1-step nf-core/differentialabundance | Same correct 1-step result plus a 2-step `nf-core/rnaseq → differentialabundance` alternative |

### New tests added in commit 2

- `test_type_satisfies_strict_no_substring_match` — pins the strict-matching contract.
- `test_is_meaningful_input_types_rejects_placeholders` — guards the param-name detector.
- `test_planner_skips_workflows_with_junk_input_types` — end-to-end: junk workflows never appear in plans.
- `test_fastq_does_not_shortcut_to_counts_matrix_workflow` — regression guard for the rnaseq-shortcut bug, using a stand-in catalog so the test doesn't depend on real-DB rows.

Total: **11 planner pytest cases**, all passing.

## What the C2 prototype found about catalog quality (commit 1 — historical, kept for context)

The prototype was an experiment to answer: **does existing typed-port coverage produce useful plans?**

**Answer: no, not yet.** Real-DB smoke tests on 4 representative queries:

| Query | Top plan returned | Verdict |
|---|---|---|
| `--start fastq --goal-types gsea_results enrichment_results` | 1-step: `nf-core/differentialabundance` (in=`counts_matrix,samplesheet`, out=`gsea_results`) | **Wrong shortcut.** Alias chain `fastq → samplesheet` lets fastq directly satisfy a `samplesheet` input. Should require fastq→rnaseq→differentialabundance. |
| `--start vcf --goal "annotation"` | `nf-core/isoseq`, `nf-core/phageannotator`, `nf-core/rnasplice` | **Junk.** These workflows declare `input_types=["input"]` — a meaningless placeholder. Keyword "annotation" matched in names. |
| `--start smiles --goal "ADMET pbpk"` | `Aizynthfinder Retrosynthesis` with `input_types=['max_routes', 'max_depth', 'pass_max_steps', ..., 'smiles_file']` | **Schema bug.** Drug-discovery workflows have **parameter names in `input_types`** instead of data type kinds. The indexer confused params with types. |
| `--start counts_matrix --goal "enrichment" --goal-types enrichment_results` | 1-step: `nf-core/differentialabundance` | **Correct.** This is the one query where typed ports are clean enough. |

**Conclusions**:
1. The planner mechanics work — but garbage in, garbage out. **C1 (typed-port backfill) is now demonstrably the blocker**, not theoretical.
2. The `_TYPE_ALIASES` table is too aggressive in one direction (`fastq → samplesheet` lets fastq satisfy any "samplesheet" input). This is the cost of being permissive enough to bridge nf-core conventions.
3. Top backfill priorities, derived from failures above:
   - Drug-discovery workflows: re-index `input_types` to actual data kinds (`smiles_list`, `pdb_file`, `mol2_file`) not param names. Probably an indexer bug at `backend/scripts/index_all_workflows.py` worth a separate fix.
   - Any workflow whose `input_types=["input"]` is unusable for planning. Either backfill or exclude from the planner.
   - The alias `fastq → samplesheet` should be **directional** (a samplesheet describes fastqs, not the reverse). Consider splitting into `_INPUT_ALIASES` / `_OUTPUT_ALIASES`.

## What is explicitly NOT in this worktree

- **C1 backfill** — not started. The findings above should drive the priority list.
- **C2 wiring into `unified_workflow_search.search_chains`** — module exists but is not yet called from production code. Intentional: the prototype's output quality (above) is not yet good enough to expose to users. Activation gated on C1.
- **C3 (`outputs.json` manifest contract)** — design only in proposal doc.
- **C4 (chain-plan UI)** — depends on C2 being production-ready.
- **All parallelism items (P1–P6)** — separate session.

## How to review

```bash
# in this worktree:
cd /home/yzhang/biomate/.claude/worktrees/agent-aaf4e393b5ea5b614

# planner tests
python3 -m pytest backend/tests/test_chain_planner.py -v

# fallback drift tests
cd frontend && ./node_modules/.bin/vitest run server/__tests__/chain-hint-fallback.test.ts

# planner CLI smoke (requires DB symlinked or BIOMATE_AI_TOOLS_DB set)
python3 backend/lib/galaxy/ai/chain_planner.py --start counts_matrix --goal "enrichment"
```

## How to merge once approved

```bash
cd /home/yzhang/biomate
git merge --no-ff worktree-agent-aaf4e393b5ea5b614
```

Or cherry-pick the single worktree commit if you prefer.
