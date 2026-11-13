# 2026-11-13 — Drug-discovery routing fix: `input_kinds` data-shape gate, provenance & self-heal

Branch: `feat/example-routing-fixes-20261112` (off `origin/integration/next-phase`, base `7d9a04cdb9`).

## Problem

The prompt *"Rank these 500 candidates for developability and show me the top 20."* (4 uploads:
`candidate_library.csv` of 500 BACE SMILES, `1IEP.pdb`, `pilot_reference_actives.smi`,
`pilot_target_info.json`) mis-matched to the workflow **"Assay Ingestion And Ranking"** (DB id
12814) — a workflow that ingests an **assay CSV (IC50/dose-response)**, not a chemical library.

### Root cause (three independent defects, all required to produce the bug)

1. **Keyword boost on the bare word "rank".** `keyword_weights` boosted any query containing
   "rank"/"ranking", which lifted the assay-ranker regardless of input shape.
2. **The data-shape gate was dead.** `workflows.input_kinds` was `NULL` for ~96% of rows, so the
   step-8a kind gate and the relevance-floor `input_compatible` veto never fired — a
   chemistry-library user was never separated from an assay-table workflow.
3. **The relevance floor was defeated twice.** The boosted score read as `high_confidence`, and
   `input_compatible` returned `None` against a `NULL` column, so neither guard demoted 12814.

A fourth, user-facing defect: the plan/chain/pipeline chat message **leaked engine paths**
(`` `subworkflows/.../main.nf` ``) and the right panel failed to rebind for chain/pipeline
responses.

## Fixes (7 commits)

| Commit | What |
|---|---|
| `ff104f9c8a` | Stop leaking `nextflow_path` in plan/chain/pipeline chat text; `hasProposal` recognises `chain`/`pipeline` responses so the panel rebinds. |
| `cc57000206` | Thread perceived `user_input_kinds` (from uploaded datasets) into the chat + chain search paths (`_perceive_user_input_kinds`, `_resolve_task_to_workflow`, `_handle_multi_task_clarification`). |
| `707f783358` | Deterministic `rule_classify_kinds()` labeler **owned by the write path** (`index_all_workflows`, `register_ai_tool_workflows`) so re-indexing preserves the gate instead of reverting to NULL. |
| `1da206754f` | Standalone rule backfill script (`backfill_input_kinds_rules.py`) + real-DB coverage report. |
| `4669c441d8` | Chemistry-regime data gate (`_CHEMISTRY_KINDS = {molecules, structure}` in `_kinds_mismatch`), developability / virtual-screening vocab, and a **gated** rank boost (fires only for a genuine assay table: user has `{tabular}` or the query names an assay/IC50/dose-response). |
| `492796bc33` | Self-healing, version-gated rule backfill at schema init so dev/prod gain coverage with **no manual step** (the catalog DB is gitignored). |
| `73e9fd8edf` | 2026-11-13 regression-audit fixes (below). |

## 2026-11-13 regression-audit fixes (`73e9fd8edf`)

An independent audit of the full branch changeset found three real collateral issues + one honesty
gate. All were fixed before opening the PR.

1. **[MEDIUM] `rule_classify_kinds` mislabelled matrix-input tools as `{fastq}`.** The fastq cue
   fired on a bare `rna-seq`/`chip-seq`/`atac-seq` domain word, so downstream **matrix-input**
   analysis tools (e.g. `linnorm` "raw count or expression data", `degseq` "pre-calculated gene
   expression matrices", `rcsl` "scRNA-seq expression data") were labelled `{fastq}` — and the
   step-8a −25 penalty then **demoted** them for `{counts_matrix}` users. Fix: fastq now requires
   **genuine raw-read evidence** (FASTQ/reads/trimming/demultiplex); a matrix/count/expression-data
   cue with no raw-read evidence drops any fastq label (prefer `NULL` over a false positive).
2. **[LOW] IVIVE mislabel.** id 12825 "Ivive Hepatic Clearance" was `{molecules}` but IVIVE
   consumes a measured-CLint **table** → now `{tabular}` (IVIVE/intrinsic-clearance cue discards
   molecules/structure).
3. **[LOW] Dead duplicate `keyword_weights['permeability']`.** Removed the shadowed `2.0` entry
   (the `2.5` developability entry below it wins).
4. **[ROBUSTNESS] Optional-dependency import guards.** `unified_workflow_search` and
   `vector_search` guarded the optional `sentence-transformers` import with `except ImportError`,
   so a **binary-broken** transitive dep (scipy/numpy ABI mismatch raising `TypeError`) crashed
   module load. Broadened to `except Exception` — an optional dep must degrade like a missing one.

### Provenance + durable self-heal

New column `workflows.input_kinds_method` (`'rule'` | `'llm'`). The rule self-heal **owns
rule-origin rows** (method `NULL`/`'rule'`): on a rule-version bump (`_RULE_INPUT_KINDS_VERSION`
`1 → 2`) it recomputes + overwrites them and clears stale labels, but **never** touches
`method='llm'`. The LLM apply stamps `'llm'`. This self-heals the above mislabels on dev/prod with
no manual step and guarantees LLM refinements survive future rule corrections.

## Testing

- **Rule-labeler regressions** (`tests/test_input_kinds_rule_regressions_20261113.py`): `linnorm`/
  `degseq`/`rcsl` are **not** `{fastq}`; IVIVE is `{tabular}`; raw-read pipelines still `{fastq}`.
- **Self-heal/provenance** (`tests/test_input_kinds_self_heal.py`): LLM values never clobbered;
  rule-origin corrected on version bump; idempotent; bounded startup.
- **py3.9 (canonical)**: all 4 modified `galaxy.ai.*` modules load; input_kinds suites **26 passed**.
- **Full routing suite on py3.9**: **26 passed, 12 skipped, 6 xfailed, 3 failed** — all 3 failures
  (`test_8c_suppressed_when_data_shape_known_no_double_penalty` + 2 `geo_fast_path` tests) are
  **PRE-EXISTING**: they reproduce **identically** against the pristine base `7d9a04cdb9` scoring
  code (verified by swapping `unified_workflow_search.py` to the base revision). My branch
  introduces **zero** new failures.
- **Frontend**: branch's own vitest suites pass (25). `tsc --noEmit` has errors **only** in
  untracked, unrelated test files + one unchanged tracked file (`cold-start-examples.ts` — a
  missing demo-asset JSON, pre-existing on base). Zero new tsc errors from this branch.

### Routing audit (real DB, `scripts/audit_routing_prompts.py`)

With/without `user_input_kinds`, all domains route correctly: RNA-seq → `nf-core/differentialabundance`
/`rnaseq`; proteomics (raw/table) → `diaproteomics`/`msstatstmt`; variant → `variantannotation`;
scRNA → `nf-core/scdownstream`; docking → docking workflows; ADMET → `Predict Admet Properties`.
Crucially:

- **Incident prompt** (developability + 4 chemistry uploads) → `Antibody Developability` top;
  **12814 absent**. ✔ (bug fixed)
- **Genuine assay-ranking prompt** with `{tabular}` → **12814 top-1 (116.3)**. ✔ (the gated boost
  did not over-correct — a real assay table still reaches the ranker)
- **`{counts_matrix}` prompt** ("Normalize my raw count expression data") → `linnorm` restored to
  the top band (no longer buried by the false `{fastq}` penalty).

### Catalog `input_kinds` coverage (local real DB)

| | rows |
|---|---|
| rule-labelled | 1,642 |
| LLM-labelled | 2,264 |
| NULL (unlabelled) | 294 |
| **total labelled** | **3,906 / 4,200 (93.0%)** |

LLM pass: `google/gemini-3.8-flash`, 2,529 classified, 0 failed. The DB is gitignored and **not**
synced — dev/prod gain the **rule** labels automatically via the self-heal migration; the LLM
refinement is a local enhancement (re-runnable on dev with the classifier CLI if desired).

## Dev sync — BLOCKED (infra/environment, not code)

`scripts/sync_to_dev.sh` was **not** run: a pre-deploy review (per the "no speculative deploys —
predict the outcome first" discipline) determined it would fail before reaching dev, and running it
risked the host disk. Evidence:

1. **Disk at 99%, 2.0 GiB free.** The sync rebuilds the frontend Docker image (this branch changed
   `frontend/shared/workflow-response-state.ts` + `frontend/server/galaxy-assistant.ts`, so the
   frontend layer rebuilds). A node/vite build needs several GB → would fail and risk filling the
   disk.
2. **Sparse-checkout worktree missing deploy prerequisites.** `REPO_ROOT` is this worktree; the
   preflight (`sync_to_dev.sh:515‑521`) requires `infra/nfcore-patches/dualrnaseq/1.0.0.patch`,
   `backend/biomni_workflows`, `backend/nf-core-workflows/modules/biomate-ai-tools`,
   `backend/nf-core-modules` — all excluded by sparse-checkout — plus `galaxy_ai_tools.db` (absent).
   It would abort with `FATAL: … missing from checkout`.
3. **Full checkout `/Users/kky/biomate` can't deploy this branch either** — on
   `fix/resolver-real-nfcore` with ~6,649 uncommitted tracked changes, this branch locked to the
   linked worktree, and also missing `infra/nfcore-patches`.

**Remediation (for whoever runs the deploy):** free disk to ≳15 GB, then run
`scripts/sync_to_dev.sh` from a **full, clean checkout** of `feat/example-routing-fixes-20261112`
that has the workflow source dirs + `infra/nfcore-patches` + `galaxy_ai_tools.db` present. On dev the
self-heal migration (`_RULE_INPUT_KINDS_VERSION=2`) runs at Galaxy init and backfills the corrected
**rule** labels automatically; then verify `input_kinds` coverage is non-NULL on the dev DB and that
the incident prompt no longer routes to id 12814.

**Dev verification: DEFERRED** (depends on the sync). The code path is fully verified locally
against the real catalog DB (see Testing + routing audit above).

## Known open issues / next steps

- **Pre-existing** `test_8c` step-9b double-penalty bug and 2 `geo_fast_path` failures — documented,
  not in scope for this PR (reproduced on base).
- 294 catalog rows remain `NULL` (the classifier declined low-confidence rows — correct; prefer
  NULL to a false positive).
- py3.14's bundled sqlite (3.53.4) raises a false-positive FTS5 integrity-check "malformed" on the
  catalog DB (CLI sqlite 3.51.0 and `PRAGMA integrity_check` both report `ok`); the LLM apply was
  run directly (FTS-neutral — `input_kinds` is not an FTS-indexed column).

---

## 2026-11-13 follow-up — Admet Pred + raw S3 + fake-chain triage

Cold-start prompt *"Triage this library into synthesise-now and park"* (4 chemistry uploads) bound
**Admet Pred** (id **14553**), painted raw `s3://` in Workflow settings, and narrated a 4-step
"Library Triage" chain while the panel showed **1 phase**. Three independent defects (PR #398 only
partially covered match/chain; S3 strip and prose-vs-engine were open).

### Findings → fixes (landed this session)

| # | Defect | Root cause | Fix |
|---|---|---|---|
| 1 | Raw `s3://` in Workflow settings | Phase editor redacts via `cleanParamValueForDisplay`; `ParameterGroup` painted raw `param.value` | Display `cleanParamValueForDisplay` / read-only for storage URIs; form state keeps real URI until Browse |
| 2 | Orphan **Admet Pred** + empty schema | DB filename `drug_discovery/ADMET_pred` archived; `_resolve_nextflow_path` aliases to pharmacology, `_find_nf_file` did not → empty `required_params`. Search did not retire missing primary paths (`BIOMATE_ENFORCE_EXECUTABLE` default off) | (a) `_find_nf_file` domain alias parity; (b) retire id 14553 (+14591) `executable=0`; (c) indexer stores **on-disk folder** in filename, skips `_archived`; (d) self-heal `_self_heal_orphan_catalog_paths` + always-on `_orphan_catalog_ids` search filter |
| 3 | Phantom Recommended rows (`target_pdb`, `library_file`, …) | Empty schema skipped phantom-drop; viewer promoted `inline_parameters` as autoFilled | Fail closed: clear inline when schema empty (server); do not promote inline when schema empty (viewer `buildViewerParameters`) |
| 4 | Chat narrates multi-step chain over single `workflow_ga` | LLM prose unconstrained when engine bound a single card | `singleWorkflowGroundingDirective` injected into system + user format prompts |

### Tests

- **vitest** (39): `parameter-group.test.tsx`, `nextflow-workflow-viewer.empty-schema.test.ts`,
  `nextflow-workflow-viewer.display.test.ts`, `single-workflow-grounding.test.ts`,
  `smiles-list-misparse-20261020.test.ts`
- **pytest** (8): `test_find_nf_file_domain_alias.py`, `test_orphan_catalog_path_heal.py`

### Follow-up — library / molecule-design dual path

User correction: do **not** index ad-hoc step compositions as `workflow_chains` rows. Later
clarification: **both** catalog mega-chain and step-by-step must work — see
`docs/20261113_LIBRARY_MOLECULE_DUAL_PATH.md`.

| Path | When | Behaviour |
|---|---|---|
| Catalog mega-chain | Real `workflow_chains` match (e.g. ADMET-gated screening) | `chainHint` → Tier-2 curated card |
| Step-by-step | synthesise-now/park or triage+library with **no** catalog match | docking → ADMET → pharmacophore as ordinary workflows; `pipeline_steps`; `chainHint=null` |

Explicitly avoided: inventing a new "Library Triage…" catalog row; single Admet Pred for multi-step
prose. Ranking integrator still deferred (do not misuse 12814).

Tests: `frontend/server/library-triage-sequential.test.ts`.

### Sync (completed 2026-11-13)

**Result: Sync OK** — tip `a1f44c67758ce71ebbcc947cda00579a612b5950` on
`sync/pr398-onto-dev` (ancestry-safe tree + parents include feat tip `f9dd7b3ff8` and
ledger tip `895432839b`).

| Check | Evidence |
|---|---|
| Sync log | `/tmp/biomate_sync_pr398_20261113T123643Z.log` — `Public dev ancestry verified: 8e8b1b1f -> a1f44c67`; `=== Sync OK at a1f44c67 ===`; smoke PASS |
| build-info | `https://dev-public.biomate.ai/build-info.json` → `a1f44c67758ce71ebbcc947cda00579a612b5950` (`git merge-base --is-ancestor f9dd7b3ff8` = YES) |
| ledger | `/opt/biomate/.deploy-ledger.jsonl` recorded `a1f44c67` at `2026-11-13T12:50:27Z` |
| Galaxy | host `:8081/api/version` → `25.1.dev0` after unpause (container was briefly paused post-sync; unpaused to healthy) |
| Admet Pred 14553 | `executable=0` on `/opt/biomate/galaxy_db/galaxy_ai_tools.db` |
| S3 strip | frontend bundle contains `data-storage-redacted` (`index-BywRMhY8.js`) |
| input_kinds | self-heal code deployed; post-sync DB still had `2571/4233` NULL (local DB upload **skipped**: `workflows_fts integrity-check FAILED` — not a silent pass). Orphan/executable filters still gate 14553. |

**PR body:** skipped (`gh` keyring invalid) — paste block below remains the intended addition.

---

## PR #398 body update (gh failed — paste manually)

Intended addition to the PR #398 description (https://github.com/bioMate-AI/biomate/pull/398):

> **Library triage (2026-11-13 follow-up):** synthesise-now / park library triage is now a
> **sequential plan of ordinary indexed workflows** (docking → ADMET → pharmacophore), not a
> catalog mega-chain. Payload is `workflow_type: 'pipeline'` + `pipeline_steps` (task-by-task;
> `skipPipelineCollapse`). Commit: `8451b4c1e0` on `sync/pr398-onto-dev`; equivalent on this PR
> branch: `f27efabb9e`.

**`gh` error (exact):**
```
Post "https://api.github.com/graphql": Forbidden
```
Underlying auth (`gh auth status`):
```
X Failed to log in to github.com account yaoyun-dev (keyring)
  - The token in keyring is invalid.
  - To re-authenticate, run: gh auth login -h github.com
```
Code is already on `origin/feat/example-routing-fixes-20261112` (PR head); only the GitHub
description text could not be updated from this agent.
