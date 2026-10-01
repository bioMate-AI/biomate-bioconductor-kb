---
license: cc-by-4.0
---
# RealBio Benchmark — proteomics_search (real-execution capability)

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Search a real shotgun-proteomics MS/MS run against a human proteome and report, **on the
same runs**, (a) **speed** — wall-clock + search throughput (spectra/s), and (b) **recall at honest
FDR** — number of peptide-spectrum matches / peptides / proteins accepted at 1% FDR, where the 1% is
**validated by an entrapment database** (entrapment false-match rate, FMR), not by target-decoy alone.

**This is a REAL-EXECUTION capability benchmark, not an LLM-prediction item-set.** Unlike the other
RealBio tasks (which score a system's *prediction* against published ground truth), this task is scored
by **actually running the search pipeline on real data through the production execution path** and
measuring the two axes from the outputs. It is the clearest instance of RealBio's thesis — *can it run
science, not just discuss it?* — because it runs the science.

## How it is defined (consistent with the other tasks)

- **Items / inputs.** 1 ProteomeTools DDA run (accession **PXD010595**, 65,521 MS scans) searched
  against the human UniProt reviewed proteome (**20,431 proteins**) + a 1:1 shuffled-target entrapment
  set (**20,431**) + reversed decoys (**40,862**) = **81,724 searched sequences**. Phase-1 expansion
  adds a HeLa gradient, an HLA immunopeptidome set, and a defined species mixture (see
  `cases.yaml` Phase-1 notes).
- **Ground truth.** The **entrapment database** — any match to a shuffled-target entrapment sequence is
  (almost surely) wrong, so the measured FMR is the honest false-match rate independent of the decoy
  model. (Survey §14.1 source A.)
- **Metric.** Reported as a tuple per arm: `{wall_clock_s, spectra_per_s, psms@1%FDR, peptides@1%FDR,
  proteins@1%FDR, entrapment_FMR@1%}`. The honesty gate is **FMR ≤ nominal at the 1% operating point**;
  a method that finds more IDs but sits above the calibration diagonal is disqualified, not celebrated.
- **Scoring.** Objective, no LLM judge — `scripts/score_proteomics_search_benchmark.py` applies ONE
  engine-agnostic FDR estimator uniformly to every arm's normalized PSM table.

## Targets (define a pass; the measured baseline is the brute-force engine)

| Axis | Target | Rationale |
|---|---|---|
| **Speed** | **≥ 5× faster end-to-end than the brute-force (Comet) baseline** | Fragment-ion indexing is the survey's §2 dominant speed lever; the measured fast engine is 5.3× end-to-end. |
| **Recall** | **≥ baseline #peptides@1%FDR** (no regression) and report the gain | A faster engine must not cost identifications; the measured fast+rescored stack is +162% peptides. |
| **Calibration (honesty gate)** | **measured entrapment FMR ≤ 1.3% at claimed 1% FDR** | Enforces the 2025 entrapment-literature requirement; any recall gain must be entrapment-clean. |

## How to run (the harness is committed)

This task is wired to the existing proteomics search harness (NOT a `predictions.jsonl`):

```
evaluation/datasets/proteomics_search_benchmark/   # cases.yaml, main.nf, prepare_search_db.py, normalize_*.py
scripts/score_proteomics_search_benchmark.py       # uniform FDR scorer -> metrics.json + calibration.tsv + pareto.tsv
```

1. Validate the DAG at zero cost: `nextflow run evaluation/datasets/proteomics_search_benchmark/main.nf -stub-run`
2. Real run: stage mzML + FASTA to S3, run `main.nf` with `--mzml --target_fasta -with-trace`
   (speed is read from the executor trace, never a tool's own log).
3. Score: `scripts/score_proteomics_search_benchmark.py --psms <normalized tables> --trace <trace>
   --claimed-fdr 0.01 --entrapment-ratio 1.0 --out .`

Every tool version is a pinned biocontainer tag; the DB build is `--seed`-deterministic; the FDR scorer
is applied uniformly to all engines (survey §14.4 fair-comparison controls).

## Current measured result (full report + provenance)

Measured 3-arm head-to-head (one ProteomeTools run, identical FASTA/tolerances/mods/hardware, uniform
FDR scorer, every arm entrapment-validated):

| Arm | end-to-end | #peptides@1%FDR | entrapment FMR @1% |
|---|---|---|---|
| Comet (brute-force baseline) | 153.1 s | 73 | 0.00% |
| Sage (fragment index) | ~29 s (**5.3×**) | 137 | 0.54% |
| Sage + Mokapot (index + rescoring) | ~42 s | **191 (+162% vs baseline)** | 0.24% |

Full benchmark report (objective / methods / full table / caveats / provenance):
**`docs/20261001_PROTEOMICS_SEARCH_BENCHMARK_REPORT.md`**; detailed session log:
`docs/20260929_PROTEOMICS_SEARCH_SPEED_RECALL.md`. Live production-path proof (per-tool containers on
AWS Batch, run `fb3440ec…`): same session log §"PER-TOOL-CONTAINER default".

**Caveats (honest).** Single dataset so far (relative gains strong, absolute counts modest because
ProteomeTools is synthetic + strict 1:1 entrapment); RAM was measured on the docker wrapper not the
tool; broader PXD sets (Phase 1) would strengthen generalization. See the report §7.

**Attribution.** Sage: Lazear, *J. Proteome Res.* 2023 (MIT). Mokapot: Fondrie & Noble (Percolator
family; Apache-2.0). OpenMS/Comet: Eng et al.; OpenMS (Apache/BSD). Data: ProteomeTools (PXD010595).
BioMate did not author these tools — it composes, runs, and benchmarks them on the production path.
</content>
