# code_harvest — BioMate's accumulated workflows + fix-history as coding-track data

Harvests two already-existing historical assets into coding-track datasets (per
`docs/20261005_LEVERAGING_BIOMATE_ASSETS_FOR_CODING.md`):

1. the enriched workflow **catalog** (`backend/database/galaxy_ai_tools.db`) → `catalog_pairs.jsonl`
   — one `(intent/spec ↔ .nf)` record per catalog workflow, provenance-tiered;
2. the git **fix-history** (all branches) → `fix_triples.jsonl` — `(broken → fixed + rationale)`
   repair pairs from commits whose message says "fix" and that touch a `.nf` or the Nextflow
   executor.

The large JSONL stays **local** (git-ignored, like `docs/.../midtrain_corpus`); what is committed
is the two scripts, this README, `samples.md`, `manifest.json`, and `.gitignore`.

```
harvest_catalog.py   → catalog_pairs.jsonl   (41 MB, 4,210 records)   + manifest_catalog.json
mine_fix_commits.py  → fix_triples.jsonl     (311 MB, 2,608 triples)  + manifest_fix.json
manifest.json        ← committed merged summary (counts/yields/sizes/sha256)
```

## Data source verification (honesty)

The catalog DB **is the real enriched DB**, not a stub:
`backend/database/galaxy_ai_tools.db` = **309 MB (324,075,520 bytes)**, `workflows` table =
**4,210 rows** with `real_exec_status` populated (`ok` 690, `ok_warnings` 402, `exec_error` 798,
`fixture_failed` 277, `runnable_assumed` 109, `skip_input_type` 36, `timeout` 18,
`ran_empty_output` 3, NULL 1,877). All the required columns are present and populated:
`name` (4,210), `domain` (4,210), `description` (4,210), `params_schema` (3,057),
`step_metadata` (3,180), `filename` = nextflow_path (4,210, UNIQUE), `real_exec_status`.
No column literally named `nextflow_path` / `required_params` / `optional_params` exists — they
are derived: `filename` **is** the nextflow_path; required/optional params are split out of
`params_schema.parameters` by the `optional` flag; steps come from `step_metadata`.

## Catalog pairs — provenance tiers (real counts)

**Dedup:** the catalog's `filename` is UNIQUE, so nextflow_path is already dedup'd at the catalog
level — **4,210 distinct records, 0 duplicate paths**. The repo holds **5,100 `.nf` files on
disk** (> 4,210) because disk includes duplicate copies and generated stubs never indexed in the
catalog; we reconcile by emitting exactly one record per catalog row and resolving each row's
`filename` to its on-disk `.nf` where one exists.

| tier | definition | count | has `nf_code` |
|---|---|---:|---:|
| **receipted** | `real_exec_status ∈ {ok, ok_warnings}` — committed execution receipt (GOLD) | **1,092** | 1,092 |
| **curated** | no receipt, but `filename` resolves to a real, substantive `.nf` on disk | **2,664** | 2,664 |
| **stub** | no receipt **and** no local `.nf` (external nf-core pipeline/module not vendored here, or index-only) | **454** | 0 |
| **total** | | **4,210** | **3,756** |

All 1,092 receipted rows resolve to on-disk code; every resolved non-receipted `.nf` is
substantive (min 33 / median 184 lines — no thin placeholders among the resolved set, so "stub"
here means *no local code*, not *short code*). The 454 stubs are 364 `.nf`-path + 90 extension-less
nf-core subworkflow index entries whose code lives in external `nf-core/*` repos pulled at runtime.

Path resolution roots (in order): `backend/biomni_workflows/`, `backend/`, repo root; extension-less
filenames also try `<path>/main.nf` and `<path>.nf`.

### Record schema (`catalog_pairs.jsonl`)

`{id, name, domain, description, params:{required[],optional[],data_inputs[]}, steps[],
nextflow_path, provenance_tier, real_exec_status, source, format, family, holdout,
nf_resolved_path, nf_code?}`

## Fix triples — real usable yield

Candidate commits (message contains "fix", case-insensitive, all branches):
**842** touching `*.nf` + **369** touching `nextflow_executor.py` = **1,169 union**.
(The plan doc's "841 + 159" was an earlier snapshot; executor fix-commits have since grown to 369.)

| | count |
|---|---:|
| candidate commits (union) | 1,169 |
| commits that produced ≥1 clean pair | **1,046** |
| **usable repair triples** | **2,608** |
| — `.nf` triples | 2,249 |
| — executor triples | 359 |
| bulk-regeneration commits skipped (> 50 files) | 83 (85,085 files) |
| dropped: new-file/delete/rename (empty side) | 221 |
| dropped: whitespace-only | 4 |
| dropped: diff > 2,000 lines | 4 |
| dropped: binary | 0 |

Usable triples (2,608) exceed the commit count because one targeted fix commit often repairs
several `.nf` files. The **83 skipped bulk commits** are mass `.nf` regeneration sweeps (one
touched ~2,800 files); their per-file diffs are near-duplicate, low-signal, and they would both
dominate the dataset and make mining intractable — so each such *commit* is dropped wholesale as
noise (documented filter `MAX_FILES_PER_COMMIT=50`), not silently. Honest usable yield from the
1,169 candidates = **2,608 clean triples across 1,046 commits**.

### Record schema (`fix_triples.jsonl`)

`{commit, short, date, file, message, kind:("nf"|"executor"), lines_added, lines_deleted,
before, after}` — `before`/`after` are the full file content at the commit's first parent / at the
commit.

## How this feeds the coding track

**(a) Retrieval / adaptation library.** All 4,210 catalog records (receipted + curated + stub)
feed the `convert-to-nextflow` / `adapt` skill: retrieve the nearest known-good workflow by
intent/description and modify it. Breadth is the value — `nf_code` (3,756 records) gives the
adaptable template; stubs still contribute routing/intent coverage. Embedding is **out of scope
here** (we emit pairs only); it wires into the existing `UnifiedWorkflowSearch` infra later.

**(b) Positive code-SFT pairs** `(intent/spec → .nf)` and reverse `(.nf → explain)`:
- **receipted (1,092)** — highest weight (graded "it ran" positive, the benchmark-gold tier);
- **curated (2,664)** — real signal, lower weight, labelled by provenance (no receipt ≠ broken);
- **stub (454)** — excluded from code-SFT (no code), retained for routing/retrieval only.

**(c) Repair-SFT triples** from `fix_triples.jsonl`: `(broken code + commit rationale → fixed
code)`, 2,608 pairs — the autofix/repair competence the live loop can't cheaply manufacture,
seeded for free from history.

## Leakage note (family-level split — mandatory before any SFT export)

A record is tagged **`holdout=true`** when its workflow **family** appears in a benchmark/eval set,
so SFT export is a **family-level** split, not a row-level one. The holdout family set is built from
the **62** `workflow:` family tokens referenced across `evaluation/datasets/*/cases.yaml`
(`nf-core/rnaseq`, `sarek`, `atacseq`, `chipseq`, `methylseq`, `alphafold`, `molecular_dynamics`,
`reinvent4_lead_design`, `cipa_cardiac_safety_ode`, … normalised to slugs). The
`evaluation/datasets/nextflow_coding/` benchmark itself is **tool-free and generic** (bash/python/
snakemake→Nextflow idioms: greeting, wordcount, sort, fanout; generic fix bugs) — it references **no
bioinformatics workflow family**, so it contributes 0 bio-families to the holdout set directly; the
family coverage comes from the selection/param benchmarks that *do* name real families.

Result (real counts):

| | records |
|---|---:|
| `holdout=true` total | **53** |
| — curated | 33 |
| — stub | 20 |
| — **receipted** | **0** |
| SFT-exportable (holdout=false): receipted / curated / stub | 1,092 / 2,631 / 434 |

Per the no-data-exclusion rule, holdout rows stay **in** the harvest (provenance-labelled), and are
separated by **reporting**: any SFT/train export must filter `holdout == false`. Notably the entire
**1,092-row receipted GOLD tier has zero leakage** against current eval families, so it is fully
SFT-exportable.

## Reproduce

```bash
python3 evaluation/datasets/code_harvest/harvest_catalog.py   # ~seconds → catalog_pairs.jsonl
python3 evaluation/datasets/code_harvest/mine_fix_commits.py  # ~25 min  → fix_triples.jsonl
# manifest.json is the merged summary of the two per-script manifests.
```

Counts above are the **real** output of these scripts against this repo's DB + git history on
2026-10-05 (branch `cursor/tutorial-live-recording-and-report-editing-4ea7`), not estimates.

## Needs dev/S3 to extend (not blockers here)

- The **454 stub** entries (external nf-core pipelines/modules) have no vendored code; pulling their
  real `.nf` (nf-core clone / dev checkout) would promote many to curated and widen the code-SFT set.
- The plan doc's **15,641 Bioc-KB validated steps** and **2,129 session-doc fix-chains** are
  additional repair/structured-code sources not harvested here (separate extractors); this task
  covered the catalog + git `.nf`/executor fix-history only.
