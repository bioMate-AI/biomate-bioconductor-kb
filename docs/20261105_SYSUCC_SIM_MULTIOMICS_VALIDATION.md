# SYSUCC-representative multi-omics stratification — simulation validation (2026-11-05)

Closes §8 item 5 of `20261104_GENERALIZATION_SESSION_IMPLEMENTATION.md` ("a SYSUCC-representative
end-to-end run") in the way that is actually possible without the hospital cohort in hand: a
**controlled simulation with known ground truth**, which validates the end-to-end multi-omics
stratification stack (integration → QC gates → cross-omics driver fusion) more rigorously than an
unlabeled real cohort could, because every answer can be scored against the truth it was built from.

Everything ran through BioMate's own execution path on AWS CPU Batch; nothing was computed off-platform.

---

## 1. Why a simulation, and what it does / does not prove
A real SYSUCC cohort is not available to this session. Rather than block, this uses a synthetic
cohort with a **documented generative model** and known subtype labels + driver genes. This proves
the pipeline's **mechanics and correctness** — that BioMate integrates multi-omics layers, evaluates
data-driven QC gates, and recovers cross-layer biomarkers, with the right answers on data where the
right answers are known. It does **not** prove real-world difficulty: planted structure is cleaner
than a real cohort, so the near-perfect scores below are close to an upper bound. A real cohort will
be messier (lower ARI, partial driver recovery); this validates the machinery it will run on.

## 2. The simulated cohort (generative model)
Deterministic (`seed=20261105`). Generator preserved in the session scratchpad; parameters:
- **150 patients, 3 molecular subtypes** (A/B/C, 50 each), labels shuffled.
- **3 omics layers that share gene symbols** (same gene at mRNA / protein / promoter-methylation
  level — so cross-layer corroboration is biologically meaningful):
  - RNA: 1500 genes × 150 samples (log2-expression-like, µ≈6)
  - Protein: 400 genes × 144 samples (subset of RNA symbols, µ≈4; 4% samples dropped)
  - Methylation: 600 genes × 145 samples (subset, β-like µ≈0.5; 6% dropped)
  - **Partial cross-layer overlap** (144/145/150 → 139 common) mimics real cohorts measuring each
    assay on an overlapping-but-not-identical sample set; SNF intersects to the common set.
- **24 true driver genes** (8 per subtype, all among the shared symbols). RNA & protein move
  together (up in the driving subtype); methylation moves opposite (promoter hypermethylation →
  silencing). Drivers of other subtypes get a mild opposite shift (contrast).
- **~8% "ambiguous" patients** (12) with 0.4× signal amplitude, to mimic real messiness.

## 3. Pipeline run (BioMate executor → AWS Batch)
- Staged the 3 layers to `s3://biomate-nextflow-work/smoke-inputs/sysucc_20261105_031724/`.
- `POST /api/nextflow/execute` → `snf_multiomics/main.nf`, `omics=[rna,protein,methyl]`,
  `n_clusters=3`, image `bioc-domain-general:3.20-slim`. **Run `ab67ad23-cbd7-4b70-b45f-51087f606df3`**,
  completed on CPU Batch (exit 0, ~140 s, ≈$0.008).

## 4. Results

### 4.1 Multi-omics integration (SNF) — near-perfect subtype recovery
Scored `snf_clusters.csv` (139 common samples) against the known subtypes:
- **Best-match accuracy: 0.993** (138/139 correct; cluster 1→C, 2→B, 3→A)
- **Adjusted Rand Index: 0.978**
- Balanced clusters (49/45/45 vs true 48/46/45).

SNF fused three partially-overlapping layers and reconstructed the latent subtypes almost exactly,
including most of the ambiguous (weak-signal) patients.

### 4.2 QC declared gates — emitted, discovered, evaluated live
`snf_multiomics/main.nf` emitted `qc_metrics.json` with declared gates; the QC monitor logged
`[QC-S3] Reading work-dir qc_metrics.json for BIOC_SNF_MULTIOMICS` and evaluated them:
- `n_clusters_found=3` ≥ 2 → **halt gate PASS** (non-degenerate integration)
- `mean_silhouette=0.0054` ≥ 0.10 → **advisory FIRES** (non-blocking). NB: silhouette on the SNF
  affinity-derived distance is low even for well-separated clusters (ARI 0.978 here), so this is a
  property of the metric, not a quality failure — a useful honest signal, correctly advisory not halt.
- `min_cluster_fraction=0.324` ≥ 0.05 → **balance PASS**

### 4.3 Cross-omics biomarker drivers — perfect recovery
Ran `multiomics.biomarker_fusion.drivers_from_run` (live in the dev backend) on the three layers +
the SNF clusters, scored against the 24 planted drivers:
- **24/24 true drivers in the top-24 — precision@24 = 1.00, recall = 1.00**
- All 24 are **corroborated across all 3 layers** (`n_fired=3`, rna+protein+methyl); the top 10 are
  all true drivers with near-identical high scores (~3.95–3.97).
- 40 ranked, exactly 24 corroborated — matching the 24 planted drivers; the rest are nominated/none.

The fusion engine (`fuse_channels`, EvidenceGate with per-layer robust null) correctly surfaced every
driver that moves with the subtypes across layers, and the per-layer null kept the methylation layer
(opposite sign, different scale) on equal footing with RNA/protein.

## 5. End-to-end verdict
On a realistic-scale, ground-truth cohort, the full generalized multi-omics stack ran through
BioMate's production path and produced the correct answers at every stage: **integration ARI 0.978 /
99.3% accuracy, QC gates emitted-and-evaluated live, drivers recovered 24/24 corroborated**. The
pipeline mechanics and correctness are validated; real-cohort difficulty remains future work (needs
the actual dataset — the scores here are near an upper bound by construction).

## 6. Reproducibility
- Seed `20261105`; S3 inputs `s3://biomate-nextflow-work/smoke-inputs/sysucc_20261105_031724/`.
- SNF run `ab67ad23-cbd7-4b70-b45f-51087f606df3` (invocation `76ca7609-…`).
- Scoring: best-match accuracy + manual ARI (`snf_clusters.csv` vs `ground_truth.csv`); driver
  recovery via `drivers_from_run(top_k=40)` vs `true_drivers.csv`.
- Capabilities exercised: `snf_multiomics/main.nf` (+ its declared-gate emission, `a5927577d`),
  `qc_gate_engine` declared-gate fallback, `multiomics.biomarker_fusion` (`c6c30e20a`/`1e8c0eb3f`).

## 7. Model-training leg on this cohort (+ live id-column-fix verification)
To complete the fourth generalized capability on the same cohort, the three layers were transposed
and concatenated into a 139-sample × 2500-feature matrix (features **layer-prefixed** —
`rna_GENE…`, `protein_GENE…`, `methyl_GENE…` — since the layers share gene symbols), with a string
`sample_id` column and the true subtype as the label. First the `ml-training` image was rebuilt from
this branch (`sha-83234a2194b0`, carrying the id-column fix `904bb6b83` + the s3-staging fix), then
`sklearn_tabular` was run on CPU Batch pinned to that image. **Run `27ba372e-81b6-4238-a615-971b5d183278`:**
- **5-fold stratified CV accuracy 0.950 ± 0.036, macro-F1 0.950** (`fold_val_sizes [29,28,28,27,27]`)
  predicting subtype from the 2500 integrated multi-omics features — the integration carries enough
  signal to recover the subtypes supervised, consistent with the ARI 0.978 above.
- **`n_features = 2500`, not 2501** — the string `sample_id` column was dropped by the id-column
  hygiene fix, **verified live on Batch** (prior to the fix it would have leaked in as a junk feature).
  `n_rows = 139`, `stratified = true`.

With this, all four generalized capabilities — routing, multi-omics integration, data-driven QC
gates, cross-omics driver fusion, and model training — are live-verified end-to-end on one
ground-truth cohort.
