# A rigorous multi-regime evaluation of an immune virtual-cell foundation model against simple baselines

Draft benchmark write-up. Recorded 2026-11-09. All numbers from committed artifacts this session.

## Summary

We evaluate an immune multi-omic foundation model (FM; 6-channel hybrid encoder — RNA / protein / ATAC /
TCR / knowledge / genetics) against properly-tuned simple baselines across single-channel, multi-channel,
and perturbation tasks, under group-disjoint splits, converged solvers, and matched nulls. **The FM does
not beat simple baselines on any supervised IN-DATASET task we could measure — and — under rigorous hardening — it does NOT
robustly win zero-shot cross-dataset transfer either (raw RNA beats it on gold-label accuracy).** It ties PCA on annotation
(at proper convergence), loses to raw RNA and to protein on stimulation classification, and its learned
multi-omic *fusion* is actively harmful (far worse than naive concatenation). On unseen-perturbation
prediction, four learned models (including a GPU attention model) all lose to a non-parametric neighbor-
mean. The one regime where a learned component wins is **label scarcity** (a knowledge channel beats raw
by +0.14 AUPRC at ~60 labels). These results reproduce the single-cell FM literature's own skeptical
consensus (Kedzierska et al.; "one PCA still rules them all"). A preliminary single-direction test (D534→GSE239626, NMI vs the target's clusters) suggested the FM won
zero-shot transfer (FM 0.477 > PCA 0.426 > raw 0.346). **This did NOT survive hardening** (below).

## Methods

**Model.** Frozen FM encoder (`hybrid_model.pt`), 512-d embedding `z`; channels mapped per the checkpoint's
`cfg_meta` (RNA→2000 HVG, protein→35 slots via curated panel + CLR). Embeddings computed in a CUDA env.

**Representations scored.** raw (corpus-scaled HVG, 2000-d); PCA(50) of raw; knowledge (768-d pathway/TF
channel means); protein (144 ADT, CLR); naive concat(RNA,protein); fm_rna (FM, RNA-only); fm_multi (FM,
RNA+protein fused). All fed to the SAME downstream head (balanced logistic, fixed C, converged).

**Tasks / splits / nulls.**
- *Stimulation* (flu/sars vs unstim), cell-type-holdout folds, label-budget sweep; null = shuffled label.
- *Cell-type annotation* (18-class), stratified + leave-tissue-out; null = majority class; proper
  convergence (saga, tol 1e-3) — a loose tol inflates the FM's apparent margin.
- *Unseen-perturbation effect* (CZI genome-scale CD4⁺T Perturb-seq, 33,983 contrasts), leave-KO-out,
  per context; metric Pearson on top-50 residual-DE genes (mean-saturation-robust); nulls = random-
  neighbor + degree-matched.
- *Scarcity*: label-budget sweep with size-matched shuffled-gene-set null.

## Results

**1. Stimulation (single-channel) — raw wins; FM loses.** raw 0.882 > knowledge 0.846 > fm_rna 0.835 >
PCA 0.744 (AUPRC, abundant labels). The trained encoder loses to raw expression by −0.047.

**2. Cell-type annotation — FM ties PCA at proper convergence.** A loose solver (`tol=1e-2`) reported
fm_z 0.536 > PCA 0.514 (+0.022). At proper convergence the margin collapses to +0.005 (fm_z 0.472 ≈ PCA
0.466) — a tie, not a win. A single leave-tissue-out fold hinted at an fm edge under shift (unconfirmed).

**3. Unseen-perturbation — a non-parametric neighbor-mean beats every learned model.** A shared-gene-set-
weighted neighbor-mean positively predicts held-out-KO effects (+0.078 Rest, t=+28 vs random). FOUR
learned models lose to it: kernel-ridge (t=−16), feature-ridge ×2 (t=−5 to −23), and a GPU learned-
attention model (+0.027 vs +0.071, t=−16.6). The raw top-DE metric is mean-saturated — a global mean
predicts individual KOs as well as anything — mirroring the literature's "mean beats scGPT" finding.

**4. Multi-channel — protein is the strongest signal; FM fusion is BROKEN.** On stimulation: protein-
alone 0.931 > naive concat 0.918 > raw 0.882 >> fm_rna 0.835 >> **fm_multi (FM RNA+protein fusion) 0.692
(0.418 scarce)**. Adding protein *through the FM* corrupts the representation (protein encoder verified
loaded). A fresh nonlinear fusion (MLP) also loses to linear concat — **no fusion headroom**; one channel
(protein) dominates, so there is little complementary signal to fuse.

**5. Scarcity — the one learned win.** As labels drop to ~60, the knowledge channel beats raw by +0.14
AUPRC (hardened: fixed C, 30 paired draws, shuffled-null controlled), because gene-set means regularize a
tiny sample. The benefit washes out as labels grow (a prior washing out with data). This win is a cell-
type-regularizer, not a transfer mechanism: under tissue shift it reverses (the mean inherits the
compartment offset).

**6. Zero-shot cross-dataset transfer — does NOT survive hardening.** A preliminary single-direction test
(D534→GSE239626, NMI vs the target's self-derived clusters) suggested an FM win (0.477 > PCA 0.426 > raw
0.346). But on the HARDENED test — gold-label accuracy, bidirectional, 6 directed transfers across three
Cell-Ontology-labeled cohorts (io / imid / infectious_control, common named types) — **raw RNA wins**:
mean accuracy raw 0.573 > PCA 0.470 > FM 0.456; macro-F1 raw 0.497 >> FM 0.357; the FM is best in only
2/6 transfers. The preliminary win was an artifact of (a) a soft cluster-coherence metric instead of
accuracy, (b) a single direction, and (c) a target with a very different gene panel that penalized raw's
alignment. **Conclusion: the FM does not robustly beat raw even in zero-shot cross-dataset annotation.**

## Discussion

These results are **consistent with the single-cell FM literature's own re-evaluations**, not an outlier.
Kedzierska et al. ("limits of zero-shot foundation models in single-cell biology") and subsequent
benchmarks find Geneformer/scGPT underperform HVG+PCA / scVI / logistic regression; one benchmark reports
a *mean-expression* baseline beating all scGPT variants (our mean-saturation result); "one PCA still rules
them all" shows PCA beats FMs on perturbation. The rigor that exposes this — tuned baselines, converged
solvers, matched nulls, group-disjoint splits — is the rigor many original FM papers did not apply.

Working deep multi-omic models *do* exist, but they are task-specific VAEs (totalVI for CITE-seq), not
transformer "LLMs." Our broken FM fusion is therefore an implementation/training failure (undertrained
omic encoders), not an inherent impossibility.

**Where the FM could still earn its place** is the regime our in-dataset supervised evals structurally
cannot test: **zero-shot cross-dataset transfer and atlas integration** — a fixed embedding mapping a new,
unlabeled cohort into a shared space, where PCA must refit and cannot transfer. That is evaluated in a
companion test; it is the single result that could change the verdict.

## Limitations

Single labeled donor (D534) for stim/annotation — no cross-donor generalization measurable; top-DE metric
is oracle-gene-selected (fair across methods); paired t-stats are over draws on the same cells, not
independent replicates; the FM checkpoint is one model (no retrained fusion); responder stratification
(the clinical task) remains data-access-blocked and unmeasured.

## Reproducibility

All scripts + results committed under `docs/20261108_knowledge_features_baseline/`,
`docs/20261109_immune_task_scoreboard/`, `docs/20261109_multichannel/`, and the gate docs
`20261109_IMMUNE_PERTURB_*`, `20261109_IMMUNE_MULTICHANNEL_FUSION_BROKEN.md`, `20261109_SESSION_AUDIT.md`.
