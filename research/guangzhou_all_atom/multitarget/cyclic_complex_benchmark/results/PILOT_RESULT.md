# Pilot result (Boltz-2, 25 samples/complex, 2026-10-26) — 26 of the 40 pre-registered complexes ran

**Stop rule (PREREG, primary threshold DockQ ≥ 0.23): oracle − default = 15.4 pp (95 % cluster-bootstrap CI 3.8–30.8) → ≥ 10 pp → NOT triggered; Stage B may proceed.** The gate passes narrowly: the lower CI bound is below 10 pp, and at the secondary threshold (DockQ ≥ 0.49) the gap is 7.7 pp [0–19], i.e. below it.

| selector (top-1 success, DockQ ≥ 0.23) | all (n=26) | strict canonical (18) | non-canonical (8) |
|---|---|---|---|
| default (Boltz `confidence_score`) | 80.8 % [65, 96] | 77.8 % | 87.5 % |
| ipTM | 76.9 % [62, 92] | 72.2 % | 87.5 % |
| random sample (expectation) | 80.3 % [68, 92] | 75.8 % | 90.5 % |
| **oracle best-of-25** | **96.2 % [88, 100]** | 94.4 % | 100 % |
| ring-validity-filtered default | 80.8 % (gain 0.0) | | |

What it says, and does not say:
- **Boltz's default pick is no better than a random sample here (80.8 % vs 80.3 %)**, and ipTM is slightly worse. Within-complex ipTM AUROC = 0.56 (only 10 of 26 complexes have mixed outcomes); pooled 0.68 is mostly between-complex difficulty. Consistent with "confidence is a weak ranker for cyclic peptides" — but with n = 26 and 26 independent clusters this is a pilot, not evidence.
- **The whole headroom is 4 complexes** (`8WSS_5`, `8ZEB_2`, `9T26_2`, `9Z2H_1`) where the default misses but another sample succeeds; one complex (`8UUI_3`) is solved by no sample. 15.4 pp = 4/26.
- **High base rate (≈80 % of random samples already succeed)** → ceiling effect; the DockQ ≥ 0.49 gap is smaller still. Easy complexes may partly reflect training-set exposure (Boltz-2 cutoff 2023-06 is secondary-source only; Chai-1 unknown).
- **Ring closure is not guaranteed:** 74.9 % of samples overall have a valid closed ring; some complexes as low as 24 % (`8X8L_3`). Boltz's `cyclic: true` adds no covalent bond. Filtering on ring validity changed nothing in this pilot.
- **Selection bias — 14 of 40 did not run, and not at random:** 2 YAML-typed CCD codes (fixed, rerunnable), 8 complexes with PDB components absent from Boltz's bundled library (`A1…`, `XAK`, `M70`; not runnable as-is — these are the newest, most leakage-clean depositions), 4 GPU-OOM on a 16 GB T4 (largest receptors). The scored 26 skew older/smaller/canonical. **The earlier "98 runnable post-cutoff complexes" claim is wrong**: the runnable flag assumed every CCD code resolves.
- Job status "SUCCEEDED" was meaningless for these runs: the Batch wrapper swallowed the driver's exit code (fixed, `submit_cofold.sh`).

**Claim status: NO claim that a selector is "best" — the selector has not been built or tested.** What the pilot supports: there is measurable headroom (≈4–31 pp) and the default selection is weak, so Stage B (train a selector on pre-cutoff complexes, evaluate once on post-cutoff) is justified but underpowered at n ≈ 26–60. Before Stage B: rerun the 2 YAML-fixed complexes; decide the 8 missing-CCD (parent-residue substitution as a separate, non-primary tier, or exclude and say so); move the 4 OOM to a larger GPU; verify the Chai-1/Boltz-2 cutoffs from primary sources.
Files: `pilot_results.json`, `scripts/pilot_analysis.py`. Samples/scores: S3 `cofold_bench/samples/boltz/` and scratch `pilot_scores.jsonl` (650 rows) — copy the jsonl into `results/` next.
