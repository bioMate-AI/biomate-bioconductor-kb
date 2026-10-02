# Platform-wide Fabrication Audit — "Analyze/Quantify" RNG stubs

**Date:** 2026-10-02
**Author:** Yaoyun Zhang
**Trigger:** The MERFISH validation found a *deceptive* RNG-fabrication stub (fake Moran's I via
`random.*`, unlabeled, fake `versions.yml`). This audit checked whether that was isolated.
**Outcome (after correction): largely yes** — only **2** genuine issues remain beyond the
already-rewired MERFISH; a first crude pass over-flagged 9 honest labeled-demo workflows (see the
MAJOR CORRECTION below).

## Method (static, free — no Batch)

Scanned every `executable=1` workflow's `.nf` on disk (3,714 files). Flagged **high-confidence
fabrication** = (RNG call `np.random.*` / `random.*` / `runif`/`rnorm`) **AND** writes an output
(`to_csv`/`savefig`/`json.dump`/`saveRDS`/…) **AND** does **not** read any input — computed on
**code lines only** (comments stripped, so anti-fabrication guard comments don't false-positive).

## MAJOR CORRECTION (2026-10-02): my first pass OVER-DISABLED — 9 of 11 were FALSE POSITIVES

My first crude regex pass flagged **11** and disabled all. A rigorous **audit-gate re-read of each
workflow's actual control flow** (not regex) found that **9 of the 11 were false positives** — they
do **real analysis on real input** and only synthesize when input is absent, writing an **explicit
"DEMO MODE / synthetic / provide X for actual analysis" notice**. That is an *honest labeled demo
fallback*, categorically different from deceptive fabrication.

The crux distinction this audit now draws:
- **Deceptive fabrication** (the real target): RNG → output, **no real path even with input**,
  **no disclosure**, often a `versions.yml` claiming tools it never ran. → MERFISH's OLD stub. Fix =
  rewire (done: real squidpy).
- **Honest demo fallback** (NOT a violation): real analysis on real input; synthetic only when input
  is None; clearly labeled synthetic in the output. → the biomni "Analyze/Quantify" workflows.

The false negatives in my first regex: it only inspected the demo branch and missed the real path
(`flowio`/`io.imread`/`shutil.copy`/`subprocess` readers), and ignored the "DEMO MODE" labels.

### Re-enabled (9 false positives — real analysis + labeled demo fallback)
`metal_meta_analysis` (14446, runs real `metal`), `Analyze Flow Cytometry Immunophenotyping` (10612,
real `flowio` gating), `Analyze Cfse Cell Proliferation` (10691), `Analyze Cell Migration Metrics`
(10569, real `io.imread` tracking), `Analyze Myofiber Morphology` (10571), `Analyze Cell Senescence
And Apoptosis` (10605), `Analyze Mitochondrial Morphology` (10613), `Quantify And Cluster Cell
Motility` (10615), `Quantify Cell Cycle Phases` (10616).

### Kept disabled (2 — genuine issues)
| id | workflow | why still disabled | fix |
|---|---|---|---|
| 10657 | Analyze Comparative Genomics And Haplotypes | HYBRID — runs real `bwa` **but** writes **unconditional** fabricated divergence times (`random.randint`, NOT demo-gated) + "this would contain…" placeholder | strip the fake lines; add real variant/haplotype calling |
| 10572 | Decode Behavior From Neural Trajectories | no real file ingestion (inline-JSON only); synthetic disclosed **only in comments**, not in output | add real neural-data file read + a non-comment DEMO label |

(DB — gitignored `galaxy_ai_tools.db`, rides the sync. Net: 2 disabled, 9 re-enabled;
`executable=1` = **4152**.)

**Lesson (the honest one):** my platform-wide "fabrication is rampant (11 stubs)" claim was wrong —
it was **2**, plus the already-rewired MERFISH. A crude RNG+write−read regex conflated honest
labeled-demo fallbacks with deceptive fabrication. The audit-gate (re-reading each one, prompted by
"really?") caught the over-disable. Verify control flow, not regex, before disabling a workflow.

## Deliberately NOT flagged (verified legitimate)

- **Infrastructure / array packages** where generating a random array **is the package's purpose**:
  BumpyMatrix, DelayedRandomArray, TileDBArray, LoomExperiment, chihaya, ExperimentSubset,
  CardinalIO (an imzML **I/O round-trip** demo). These are kept executable.
- **Simulations** where RNG is correct by design: `Simulate Microbial Population Dynamics`,
  `Virtual Patient Cohort`.
- **`Hts Plate Qc Hit Calling` (14516)** — fabricates **but honestly labels** output
  `data_source='synthetic_demo'`, so it is not deceptive. Left executable; should be demo-gated in
  the UI and ideally rewired.
- **`Multiome Rna Atac` (14609)** — FALSE POSITIVE: its `random.*` is only in header comments that
  document a **prior** fabrication that was **already fixed**; the code reads real matrices and
  computes peak-to-gene links. Non-fabricating.

## Remaining work (only 2 workflows)

The 9 re-enabled workflows need **no rewire** — they already do real analysis on real input (their
quality gap is that the DEFAULT, no-input run produces a *labeled* synthetic demo; a UX improvement
would be to require real input or surface the "DEMO" label prominently, but that is not fabrication).

The two genuinely-disabled workflows to fix:
1. **`10657` Analyze Comparative Genomics And Haplotypes** — strip the unconditional
   `random.randint` divergence/variant lines + the "this would contain…" placeholder; keep the real
   `bwa` alignment and add real variant/haplotype calling (`bcftools`/`samtools`), then re-enable.
2. **`10572` Decode Behavior From Neural Trajectories** — add a real neural-data file read
   (`np.load`/`pd.read_csv`) so it ingests recordings, and move the synthetic notice from a comment
   into the emitted output; then re-enable.

(For reference, the prior MERFISH + sc3 rewires are the template: real tool + input handling +
container + Batch validation — see `docs/20261001_MERFISH_SPATIAL.md`.)

## Class guard (shipped) — `scripts/audit_fabrication.py`

The scan is now a reusable **hard gate**: `scripts/audit_fabrication.py` enforces the invariant
*no `executable=1` workflow fabricates its outputs* (RNG → written output, no input read; code lines
only, with a reviewed `ALLOWLIST` for legitimate RNG — array/IO packages, simulations, honestly-
labeled demos). Exit 0 = clean, exit 1 = an executable fabricator exists. Wired into
`docs/PRE_SYNC_CHECKLIST.md` (step 4b): run it whenever a workflow `.nf` or an `executable` flag
changes, and never sync a DB that trips it. The guard now exempts real reads (`flowio`/`io.imread`/
`shutil.copy`/…), real external tools, and honestly-LABELED synthetic/demo fallbacks — so it targets
only *deceptive* fabrication (RNG→output, no real path, no disclosure). Current state: **PASS**
(2 disabled: 10572, 10657; 9 re-enabled; 11 legitimate-RNG entries allowlisted). This closes the
deceptive-fabrication *class* — a new unlabeled fabricating stub with no real path fails the gate.
(Limitations, need human review: a HYBRID that runs a real tool AND fabricates part of its output
like 10657; and a workflow that merely *claims* a demo label while never doing real work.)

See also `docs/20261001_SPATIAL_OMICS_VALIDATION_PLAN.md` (execution-validation thesis) and
`docs/20261001_MERFISH_SPATIAL.md` (the first instance + its real rewire).
