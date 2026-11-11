# SYSUCC / "advantaged drug development" workflows — DB audit (2026-11-10)

**Question:** were the SYSUCC (Zhongshan / 中山大学肿瘤防治中心) drug-development workflows
added to `galaxy_ai_tools.db`, all relevant fields populated, and is the dev DB updated?
What's done, what's left.

**Method:** direct `sqlite3` queries on the local
`backend/database/galaxy_ai_tools.db` (4,227 workflows) + an SSM read-only probe of the
dev DB on `i-06696b0d91f4346e0` (`/opt/biomate/galaxy_db/galaxy_ai_tools.db`, mounted
`/app/database` in `biomate-galaxy-dev`).

---

## 1. Added to the DB? — YES

All SYSUCC-modality drug-dev workflows are present as `workflows` rows, FTS-indexed and
routable. The set, by modality:

| Modality | Workflows (id) |
|---|---|
| Antibody / bispecific | scfv_antibody_design (12856), bispecific_antibody_design (12911), bispecific_format_triage (12934), **Antibody Antigen Complex / Boltz-2 (14665)** |
| ADC | adc_design (12928) |
| CAR-T | cart_construct_design (12926), in_vivo_cart_codesign (12935) |
| HLA / epitope / TCR | epitopeprediction, antigen_resolution, hlatyping, powertcr (12076), immuneapp, immuneapp_hla_screen, **MHC Binding Prediction / MHCflurry2 (14666)** |
| EBV / vaccine (NEW) | **Bcell Epitope Immunogen (14667)**, **Surface Epitope Mapping (14668)** |
| Peptide / structure | cyclic_peptide_design (14448), Cyclic Peptide Cofold (14663), boltz (14470), Boltz Structure Prediction (14614) |
| Assay / PK | synergyfinder (12502) + 2 variants (14120/14121), hts_plate_qc_hit_calling (12882), Nca Pknca / PKNCA (10642) |

The four **newest** (built this program, Nov 2026) and their add timestamps:
`14665 Antibody Antigen Complex 2026-11-09`, `14666 MHC Binding 2026-11-09`,
`14667 Bcell Epitope Immunogen 2026-11-10 19:38`, `14668 Surface Epitope Mapping
2026-11-10 20:30`. All four are FTS-indexed (verified: `MATCH` by name returns each).

## 2. Dev DB updated? — YES, byte-identical

- Local DB md5 = **`96440b7643e69365eccc08525a6b1484`**
- Dev DB md5 = **`96440b7643e69365eccc08525a6b1484`** (SSM `md5sum`) — **identical**
- Dev workflow count = **4227** = local 4227
- All four newest rows (14665–14668) present on dev with identical timestamps, including
  the two added **today** (14667 19:38, 14668 20:30). The DB sync
  (`deploy_databases()`, S3-staged + MD5-gated + FTS-integrity-gated) ran after 20:30.

The DB is **not** git-tracked (349 MB); it reaches dev only via `scripts/sync_to_dev.sh
deploy_databases()`. Dev == local as of this audit.

## 3. Field population — core fields populated; the rest is advisory, verified by code

Populated for all: `name`, `domain`, `description`, `workflow_json`, `filename`
(nextflow_path), `step_count`, `tags`, `input_types`, `output_types`, `tools_used`,
FTS index.

The remaining empty columns were initially flagged as gaps. **Reading the consuming
code (not assuming) overturned two of them** — this is the important correction:

1. **`params_schema` empty — NOT a functional gap for these workflows.** The prefill /
   workflow-generation path (`ai_assistant.py:2761` and `:3062`) calls
   `_parse_nextflow_params(filename)` — it parses the **`.nf` file live** for
   params, types, defaults, required-levels and inline-comment descriptions. It never
   reads the `params_schema` DB column. Verified: the production `param_re` regex parses
   all four newest `.nf` files cleanly (bcell_epitope_immunogen 7 params,
   surface_epitope_mapping 6, antibody_antigen_complex 3, mhc_binding_prediction 5, all
   with defaults). `params_schema` is populated only for the **bioconductor** cohort (by
   `enrich_bioc_step_params.py`) as a cache; for nextflow workflows the `.nf` is the
   source of truth, which is present + bind-mounted on dev. **No generator needed — and
   a generator would have forced a needless 349 MB DB re-sync.**
   Minor real nit (not a blocker): the numeric defaults in these `.nf` are **quoted**
   (`params.window = '7'`, `cutoff_sd = '0.5'`), so the parser types them `string` →
   the panel renders text inputs, not number inputs with range hints, and numeric
   rule-inference won't fire. Fixing means un-quoting in executed `.nf` code (risk-gated
   edit, cosmetic payoff) — left as a low-priority polish, not done speculatively.
2. **`real_exec_status` NULL — NOT a routing penalty.** Policy is explicit in
   `unified_workflow_search.py:240-244`: *"Null / unknown status AND null verdict → 0.0
   (neutral, NEVER a penalty) … they must not be pushed below scored-bad ones for lack
   of data."* The execution bonus is capped at **±2.0** and "only re-orders near-ties"
   (semantic/FTS/name signals dominate by 1-2 orders of magnitude). So these rank like
   any validated workflow minus only a ≤+2.0 tie-breaker.
   There is also **no recoverable Batch evidence** to cheaply record: the
   antibody_antigen_complex `interface_iptm 0.964` is, per its own doc
   (`20261109_…_ANTIBODY_COMPLEX.md:62`), a **wiring smoke test on a demo CD19
   fragment, "not a validated epitope"** — the authors flag that "first real run should
   fold a known antibody–antigen pair." Recorded status (synergyfinder `ok_warnings`,
   powertcr `exec_error`) comes from real runs; back-filling 14665–14668 from a smoke
   test would violate "numbers from source not memory" / "run status not trustworthy."
3. **`annotation_v2` NULL** — advisory v2 scientific-annotation enrichment, not run on
   this cohort. Does not gate routing or execution.
4. Thin `step_count` on a few (adc_design = 0; several = 1) — honest stub-depth
   (bispecific = honest stub per memory), not missing data.
5. Apparent **duplicate pairs**: a lowercase executable-`.nf` row (e.g.
   scfv_antibody_design 12856) **and** a Title-Case subworkflow-stub row (e.g. Scfv
   Antibody Design 14530) for scfv / bispecific / hts_plate / boltz. Worth a dedup so
   routing doesn't split rank; involves deleting rows → confirm before acting.

## 4. What's actually left (re-scoped after reading the code)

Nothing here is a functional gap blocking use. In value order:

1. **Real validation on real inputs** (the only scientifically meaningful item): run
   14665–14668 against *known* targets (a known antibody–antigen pair; real EBV
   antigens) — the "first real run" the authors flagged. `bcell_epitope_immunogen`,
   `surface_epitope_mapping` (biomate/workflow-tools, **CPU**) and `mhc_binding_prediction`
   (MHCflurry, CPU) are cheap; `antibody_antigen_complex` (Boltz-2) is **GPU** = a
   deliberate spend. Judge from trace+log, then write `real_exec_status` back and carry
   it in **one** DB re-sync. Gives at most a ≤+2.0 ranking nudge but real provenance.
2. **Dedup** the executable-vs-stub twins (confirm first — row deletes).
3. **`annotation_v2`** enrichment pass (advisory).
4. **`.nf` numeric-default un-quoting** (cosmetic panel polish; risk-gated edit).
5. Open modality gaps (from `project_sysucc_modality_capability`): ESMFold/developability
   (ESMFold exists id 14464; AntiBERTa2 off-limits → BALM/AbLang2/ESM-2), macrocycle
   ncAA folding (HighFold/AfCycDesign), EBV mRNA/immunogen *real* build.

## 5. Real-execution validation — DONE for 3 of 4 (2026-11-11)

Ran three of the four newest workflows on **AWS Batch** with **real inputs** (not the
demo defaults), judged from the actual output files, and wrote `real_exec_status='ok'`
(observed, `real_exec_provisional=0`) back to the local DB for 14666/14667/14668.
All three succeeded (~6 min) and **reproduced the recorded panel science**:

| id | workflow | real input | run_id | result (matches prediction) |
|---|---|---|---|---|
| 14668 | surface_epitope_mapping | RCSB 2H6O (gp350) + 5T1D (gH/gL) | `4dc4598b` | 2H6O **23 patches (21 disc)**, 5T1D **70 (68)** — exact match to panel doc; real Shrake-Rupley SASA |
| 14666 | mhc_binding_prediction | 4 published EBV A*02:01 epitopes | `5f2cc8c4` | **4/4 strong** (GLCTLVAML 74.8 nM, CLGGLLTMV 38.7 nM, FLYALALLL 13.9, YVLDHLIVV 7.6) |
| 14667 | bcell_epitope_immunogen | real gp350 (UniProt P03200, 907 aa) | `76409ce4` | top **PSSNPETLSPSTSDNS 669–684 (0.521)**, #2 **HVSTSSPAPR 714–723 (0.511)** — exact match; 25 epitopes, immunogen built |

Outputs: `s3://biomate-nextflow-work/nextflow/outputs/sysucc-validation/{fa5c63f3,b38d6eeb,03579ade}/`.
**14665 (antibody_antigen_complex, Boltz-2) stays NULL** — its only run is the demo-CD19
smoke test (not a real epitope); a real GPU run on a known antibody–antigen pair is the
remaining validation (deliberate spend).

**DB→dev propagation:** the local DB md5 changed (`96440b76…` → `2e24e549…`); the three
`real_exec_status` writes reach dev on the next full `deploy_databases()` sync
(MD5-gated, 349 MB) — not fired here (advisory field; NULL was already neutral in
ranking, so dev loses nothing by waiting for the next batched sync).

## Bottom line

Added ✔, on dev ✔ (byte-identical), routable ✔, **prefill-working ✔ (verified by
parsing the real `.nf` through the production regex), un-penalized in ranking ✔
(explicit NULL-neutral policy)**. The SYSUCC advantaged-drug-dev workflows are
**demo-ready as they stand**. The empty `params_schema` / `real_exec_status` columns are
**not functional gaps** — reading the consuming code (rather than assuming) showed
prefill parses the `.nf` live and NULL exec-status is neutral. The one genuinely
valuable remaining task is a **real validation run on real inputs** (CPU-cheap for 3 of
4; GPU/spend for Boltz-2), which is a deliberate decision, not silent churn.
