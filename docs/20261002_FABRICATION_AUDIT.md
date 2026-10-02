# Platform-wide Fabrication Audit — "Analyze/Quantify" RNG stubs

**Date:** 2026-10-02
**Author:** Yaoyun Zhang
**Trigger:** The MERFISH validation found an RNG-fabrication stub (fake Moran's I via `random.*`).
This audit checked whether that was isolated. **It was not.**

## Method (static, free — no Batch)

Scanned every `executable=1` workflow's `.nf` on disk (3,714 files). Flagged **high-confidence
fabrication** = (RNG call `np.random.*` / `random.*` / `runif`/`rnorm`) **AND** writes an output
(`to_csv`/`savefig`/`json.dump`/`saveRDS`/…) **AND** does **not** read any input — computed on
**code lines only** (comments stripped, so anti-fabrication guard comments don't false-positive).

## CORRECTION (2026-10-02): metal_meta_analysis was a FALSE POSITIVE — re-enabled

My first pass flagged **11** and disabled all. A follow-up code read (audit-gate) found
**`metal_meta_analysis` (14446) is NOT fabrication** — it runs the **real `metal` binary** on real
cohort sumstats (`shutil.copy` of the staged files → METAL script → `metal` → parse
`METAANALYSIS1.TBL`); the RNG is an **opt-in `--use_baked_toy` smoke fixture** only. The miss was a
**false negative in the guard's READS regex** (it didn't recognize `shutil.copy`/`subprocess` as
"does real work"). **Fix:** the guard now treats `shutil.copy`/`SeqIO`/`imread` as input reads and
any real external-tool call (`subprocess`/`metal`/`bwa`/…) as genuine work, so metal-class
workflows aren't flagged. **metal_meta_analysis re-enabled (`executable=1`).**

Also reclassified **`Analyze Comparative Genomics And Haplotypes` (10657)** as a **HYBRID**: it runs
real `bwa` alignment **but** writes fabricated haplotype numbers (`random.randint` divergence
times) + placeholder "this would contain…" text. **Kept `executable=0`** (its output is partly
fake); rewire = strip the fabricated lines, add real variant/haplotype calling.

## Result — 10 confirmed fabricating/ hybrid workflows → `executable=0` (metal excluded)

Each invents its results with RNG (9 purely; 10657 partially), under an "Analyze/Quantify/Decode"
name that implies real data analysis. Users running these would get **plausible-looking fake
science.**

| id | workflow | domain | what it fabricates |
|---|---|---|---|
| 10691 | Analyze Cfse Cell Proliferation | immunology | proliferation generations (`np.random.normal`) |
| 10612 | Analyze Flow Cytometry Immunophenotyping | cell_biology | immunophenotype populations |
| 10616 | Quantify Cell Cycle Phases From Microscopy | cell_biology | cell counts + G1/S/G2 percentages |
| 10615 | Quantify And Cluster Cell Motility | cell_biology | motility tracks |
| 10613 | Analyze Mitochondrial Morphology And Potential | cell_biology | morphology/potential metrics |
| 10569 | Analyze Cell Migration Metrics | bioengineering | cell trajectories (`np.random.randn` walk) |
| 10571 | Analyze Myofiber Morphology | bioengineering | myofiber measurements |
| 10572 | Decode Behavior From Neural Trajectories | bioengineering | neural-decode accuracy |
| 10605 | Analyze Cell Senescence And Apoptosis | cancer_biology | senescence/apoptosis fractions |
| 10657 | Analyze Comparative Genomics And Haplotypes | genomics | divergence times / variant counts |

(DB change — gitignored `galaxy_ai_tools.db`, rides the sync. 10 disabled; metal re-enabled →
`executable=1` = **4144**.)

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

## This is the immediate (integrity) fix — not the full fix

Marking `executable=0` **stops users from running fabrication**, which is the correct immediate
action (per the repo's no-fabrication rule: do nothing rather than ship fake output). The **full
fix is to rewire each to a real pipeline** (as done for MERFISH: real squidpy; for sc3: real SC3),
which is a per-workflow effort (real tool + input handling + container + Batch validation).

### Suggested rewire priority (follow-up campaign)
1. `metal_meta_analysis` — real METAL/METASOFT on staged GWAS summary stats (highest harm as-is).
2. The immunology/cell-biology flow/CFSE/cell-cycle set — real `flowCore`/`CATALYST`/`scanpy` on
   staged FCS / image / count inputs.
3. The bioengineering imaging set — real tracking (TrackMate/`trackpy`) + morphology on staged images.

## Class guard (shipped) — `scripts/audit_fabrication.py`

The scan is now a reusable **hard gate**: `scripts/audit_fabrication.py` enforces the invariant
*no `executable=1` workflow fabricates its outputs* (RNG → written output, no input read; code lines
only, with a reviewed `ALLOWLIST` for legitimate RNG — array/IO packages, simulations, honestly-
labeled demos). Exit 0 = clean, exit 1 = an executable fabricator exists. Wired into
`docs/PRE_SYNC_CHECKLIST.md` (step 4b): run it whenever a workflow `.nf` or an `executable` flag
changes, and never sync a DB that trips it. Current state: **PASS** (10 fabricators/hybrid disabled,
metal re-enabled as genuine, 11 legitimate-RNG entries allowlisted). This closes the fabrication
*class*, not just the instances — a new fabricating stub entering as executable now fails the gate
and forces triage. (Limitation: a HYBRID that runs a real tool AND fabricates part of its output —
like 10657 — is NOT caught by the pure-fabrication gate; those need human review.)

See also `docs/20261001_SPATIAL_OMICS_VALIDATION_PLAN.md` (execution-validation thesis) and
`docs/20261001_MERFISH_SPATIAL.md` (the first instance + its real rewire).
