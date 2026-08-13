# Alignment-QC gate: gold-standard feasibility — GO (with one caveat)

Date: 2026-08-11. The feasibility check for an "alignment trustworthiness / over-correction"
QC gate — does a gold standard exist to CALIBRATE and VALIDATE the verdict? (Without one it's
just a LISI plot.) Verified via web scan (DOIs/accessions read off publisher/GEO/GitHub;
unverified items flagged) + an S3/repo check for what's already staged.

## Verdict: GO. A real calibration battery is assemblable from verified, downloadable data.

But: **having a gold standard ≠ having a working detector.** The real Gate-1 experiment is
still unrun — *can any metric combination reliably separate over-corrected from correct on
data where we know the answer?* The gold standard just unblocks that experiment.

## What's staged locally (S3): biology yes, batch no

- `sc_multiome/` (10x RNA+ATAC) ships `celltype_labels.csv` (T, Mono, …) — **biology ground
  truth**, but a **single batch** (barcodes all `…-1`) → nothing to over-correct.
- `sc_citeseq/` (RNA+ADT): no labels. `brca_mosaic_p30/60/100`, `sc_multiome_p30/60/100`:
  matrices only, no labels.
- ⇒ **No over-correction gold standard staged.** We have the easy half (biology labels), not
  the batch / batch-confounded half — must bring it in.

## The minimal calibration battery (all verified downloadable unless noted)

| Role | Dataset | Pointer | License |
|---|---|---|---|
| Negative control (same biology across replicate batches → must fully mix) | Tung 2017 (iPSC, 3 C1 batches + ERCC) | PMC5206706 | Nature data terms |
| Positive control (known between-line DE → must be preserved) | sc-mixology / CellBench (Tian 2019) | GEO GSE118767; Bioc `CellBench` | pkg GPL-3; **raw-data license UNVERIFIED** |
| Real confounded case (natural, non-tunable) | scIB "isolated labels" + lung-spatial | figshare 12420968 | `scib` MIT / `scib-metrics` BSD-3; **dataset license UNVERIFIED** |
| Tunable confounded case (dial the degree) | **SIMULATE** — splatter groups+batches, subsample to overlap α∈{0,.25,.5,1} | github Oshlack/splatter (GPL-3); recipe per CODAL (DOI 10.1038/s41467-023-39494-2) | GPL-3 |
| External over-correction oracle to cross-check | RBET (Hu 2025) + housekeeping positive-control sets | github zlyx26/RBET | **CC BY-NC-ND 4.0 (non-commercial, no-derivatives)** |

Metrics to compute the batch-vs-bio tradeoff: scib / scib-metrics (iLISI/kBET/graph-conn vs
cLISI/ARI/isolated-label-F1), LISI, kBET — all open-source.

## The one caveat (not a blocker, but the crux of validity)

**No simulator exposes "degree of confounding" as a parameter.** splatter/scDesign3/SymSim/
dyngen model batch and biology as *separable*. The valuable case — batch *partially
confounded* with the biological group, with a *known dialable* fraction — must be
**constructed** (simulate groups+batches, then subsample to impose a chosen batch×group
composition α). This is an established recipe (scIB Simulation-2, CODAL), but it's
engineering, and the confounded-case validity then rests on the **simulator being realistic**
— exactly where to stay skeptical. Real confounded data (scIB isolated labels) gives natural
but non-tunable confounding as the reality check.

## License / commercial notes (matter if this ships as product)

- RBET is **CC BY-NC-ND 4.0** — benchmark against it, do NOT redistribute a modified version.
- `scib-metrics` is **BSD-3**, `scib` is **MIT** (not both MIT).
- CellBench raw-data-repo license + scIB dataset license are **UNVERIFIED** — confirm before
  any redistribution/commercial bundling.

## Corrections logged (don't restate the old versions)

- Kang 2018 (GSE96583) is a **positive** control (real ctrl-vs-IFNβ biology to preserve),
  NOT a clean negative control. The true same-sample-split negative control is **Tung 2017**.
- scIB DOI 10.1038/s41592-021-01336-8 (PMID 34949812).

## Gate-1 RESULT — PASSES (on controlled simulation, the honest first step)

Ran `scripts/gate1_alignment_qc_overcorrection.py` (pure-numpy, 20 seeds): simulate known
cell types × batches, sweep under-corrected → CORRECT → OVER-corrected (collapse cell types),
compute the metric panel, and test whether each metric can separate CORRECT from OVER-corrected.

**Separable batch:**
| regime | iLISI↑(mix) | cLISI↓(pure) | kBET↑(mix) | ARI↑(bio) |
|---|---|---|---|---|
| CORRECT (t=.5) | 1.94 | 1.44 | 0.92 | 0.85 |
| OVER-corr (t=1) | 1.94 | 3.66 | 0.91 | 0.00 |
- Batch-only metrics **can't tell them apart** (kBET |AUC|=0.60, iLISI 0.59 → *fooled*).
- Biology-conservation metrics separate **perfectly** (ARI, cLISI |AUC|=1.00).

**Confounded batch (60%):** at CORRECT, batch legitimately stays under-mixed (kBET 0.21,
iLISI 1.62); at OVER-corr, kBET 0.91 / iLISI 1.94 — so batch-only metrics don't just fail,
they **actively reward** the over-corrected embedding (higher "mixing"). Biology-conservation
(ARI 0.85→0.00) correctly flags it worse.

**Conclusion:** the QC gate is real, not a re-skinned LISI plot. Judging integration by
batch-mixing alone gives over-correction a passing grade (or in the confounded case, *prefers*
it); a batch+biology panel reliably catches it (|AUC|=1.00). That combined verdict IS the
product.

### Honest caveats on the Gate-1 pass
1. **Simulation, not real data** — this is the best case (known answer). It proves the metrics
   *can* discriminate in principle; it does NOT yet prove they do on real integrations. Next:
   repeat on sc-mixology/CellBench + scIB isolated-labels with real Harmony/scVI at varying
   theta/anchor-k.
2. **The discriminating signal (ARI/cLISI) needs a notion of biology to preserve** — true
   labels, pre-integration clusters, or marker sets. In deployment the user may lack ground-
   truth labels post-integration; the gate must lean on pre-integration structure / markers.
   This is the real practical constraint to design around, not batch metrics.
3. My over-correction model (linear cell-type-separation shrink) is a simplification; real
   over-correction is messier, but the qualitative mechanism (batch metric stays high while
   biology collapses) matches the LISI/erasure literature.

**Status:** feasibility GO confirmed by Gate-1. The remaining validation is real-data
reproduction (sc-mixology + scIB), which is the point at which this becomes a defensible
tool/paper rather than an internal proof.

## Gate-2 (real data) — de-risked and STAGED; awaiting one reviewed Batch run

Free de-risking done (no Batch spend yet):
- **Data staged:** scIB pancreas benchmark `human_pancreas_norm_complexBatch.h5ad` (301 MB,
  figshare file 24539828) → `s3://biomate-nextflow-work/alignment_qc/pancreas.h5ad`. This is
  the canonical multi-batch integration benchmark: human pancreas, multiple sequencing
  technologies as batches, with cell-type labels. **obs keys verified from the raw file:**
  `tech` (batch: inDrop…) + `celltype` (alpha/beta/acinar/ductal…). So run with
  `--batch-key tech --label-key celltype`.
- **Experiment authored:** `scripts/gate2_alignment_qc_realdata.py` — load h5ad → HVG+PCA →
  **real Harmony theta-sweep** (0,0.5,1,2,4,8,16) → hand-rolled metric panel (iLISI/kBET vs
  cLISI/ARI, same defs as Gate-1). Deps: **scanpy (already in the notebook image) + harmonypy
  (one pip add)** — NO scib dependency.
- **Engine has the aligner:** BioMate already ships `create_harmony_embeddings_scRNA`,
  `create_scvi_embeddings_scRNA`, `get_uce_embeddings_scRNA` subworkflows (biomni-tools image).

**Pre-run review (per the expensive-test discipline):**
- What it does: PCA once, then Harmony at increasing theta; higher theta = more aggressive
  batch mixing. Expected: iLISI/kBET rise with theta; ARI rises then FALLS once theta over-
  corrects (merges islet cell types); cLISI rises when types merge.
- Predicted verdict: at least one high-theta config is "batch-mixed but biology erased"
  (kBET≥0.8, ARI < 0.9·best) — a config a batch-only gate would PASS and the panel FLAGS.
  If NO theta over-corrects in [0,16], widen the sweep; if biology never holds even at low
  theta, the dataset/prep is off — investigate, don't just report.
- Gating deps to confirm at run time: `harmonypy` importable (pip add if not); `.X`
  normalization branch (the script auto-detects pre-normalized scIB .X to avoid double-log —
  a bug caught in self-review).
- Bug caught in review: scIB `_norm_` .X is already log-normalized; script now detects this
  (counts-layer → normalize; raw-looking → normalize; else skip) instead of blindly
  re-normalizing.

## Gate-2 RESULT — reproduced on real cells, in the regime that matters

Ran on the real scIB pancreas (16,382 cells, 9 technologies, 14 cell types) via an isolated
venv (anndata+numpy/sklearn+harmonypy, no scanpy) — a local FEASIBILITY validation, not a
product-capability claim (productization = a BioMate subworkflow, deferred; a full dev sync
was judged disproportionate/risky for one feasibility run). Scripts:
`scripts/gate2_alignment_qc_realdata.py` (scanpy variant) + `scripts/gate2_confounded_realdata.py`.

**(a) Clean pancreas, Harmony θ-sweep 0–16:** NO over-correction. iLISI rose 1.3→3.5 (batches
mixed harder) but biology HELD (ARI ~0.5, cLISI ~1.2 throughout). Pancreas cell types are
transcriptionally very distinct and Harmony is built to preserve cluster structure, so it
doesn't over-correct even when pushed. **This is the ideal null: on easy data the gate stays
quiet (no false alarm) — correct integration is achievable and achieved.**

**(b) Confounded pancreas (alpha/beta across inDrop1/smartseq2, batch ~72/28 correlated with
type), θ 0–64:**
| stage | iLISI↑ | cLISI↓ | ARI↑ | biology |
|---|---|---|---|---|
| θ=4  | 1.035 | 1.114 | **0.207** | intact |
| θ=16 | **1.117** | 1.167 | **−0.001** | ERASED |
| θ=64 | 1.114 | 1.212 | 0.001 | ERASED |

At θ≥16 biology collapses (ARI 0.21→0.00; cLISI rises = alpha/beta merged) — real
over-correction. The batch-mixing metric moves the WRONG way: **iLISI *rises* (1.035→1.117)
as biology is erased**, so a batch-only criterion would *prefer* the biology-destroying
config; only the biology panel (ARI/cLISI) flags it. **This reproduces the Gate-1 mechanism
on real cells, in the confounded regime the gate is actually for.**

### Honest verdict + caveats
- **Verdict:** the QC-gate premise holds on real data — it fires when over-correction really
  happens (confounded case) and stays silent when integration is fine (clean case). Both are
  the desired behavior.
- **Caveats (do not over-claim):** (1) local feasibility run, NOT through BioMate Batch —
  productization pending; (2) confounded case is n=648, single seed, one method (Harmony),
  one dataset — needs replication + more methods/datasets + CIs before it's a paper; (3) the
  "batch-only fooled" is *directional* here (iLISI rises 1.035→1.117; only 2 confounded
  batches keep the absolute mixing low), sharper in simulation than on this small real subset;
  (4) my over-detection threshold (`iLISI≥1.6`) was miscalibrated for a 2-batch case — the
  verdict is read from the ARI-collapse-while-iLISI-rises pattern, not that flag.
- **Next for a real tool/paper:** productionize as a BioMate subworkflow (the aligners already
  exist); replicate across sc-mixology + more scIB tasks + multiple methods (scVI, etc.) with
  seeds/CIs; calibrate the over-correction verdict thresholds on the gold standard.
