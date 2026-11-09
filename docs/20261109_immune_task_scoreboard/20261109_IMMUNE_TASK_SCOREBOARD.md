# Immune-task scoreboard — does our MODEL beat the baselines, per task

Generated: 2026-11-09. Harness: `run_bench.py` (CPU, torch-free) + `make_xs.py` / `embed_fmz.py` (the
FM-encoder embedding step). Runs on Spark `/home/yzhang/immune_fm_spark/ws_bench/`. Operationalizes
"is our model best on immune tasks?" by scoring representations against the **right baked-in
baseline/null per task**, with group-disjoint split discipline.

## Representations scored (all four, including the actual model)
- **raw** — corpus-scaled HVG expression (raw baseline)
- **pca** — PCA(50) of raw (a strong simple baseline; "one PCA rules them all")
- **know** — pathway/TF knowledge-channel means = the model's knowledge representation
- **fm_z** — the **frozen FM encoder embedding** (512-d) from `hybrid_model.pt`. Computed in env
  `~/ihlm/envpin2` (torch 2.14.1, CUDA) via the checkpoint's own `build`/embed logic (RNA-only,
  `model(... mods={'rna'}, ...)['z']`) over the 15,000 D534 cells in h5ad order; scored on the CPU
  harness with the same splits. (System python3's torch is broken — that's why the CPU harness is
  torch-free and the embedding is computed separately in envpin2.)

## Scorecard (all measured; `scorecard.json` here)

| Task | Metric | raw | PCA | know | **fm_z (model)** | null | Who wins |
|---|---|---:|---:|---:|---:|---:|---|
| **Stim-state classification** | AUPRC, pooled OOF /3 seeds, cell-type-holdout | **0.882** | 0.744 | 0.846 | 0.835 | 0.142 | **raw** (model < raw) |
| **Cell-type annotation** (18-class) | macro-F1, stratified 3-fold | 0.490 | 0.514 | 0.395 | **0.536** | 0.017 | **fm_z ✅** (model best) |
| **Unseen-perturbation effect prediction** | Pearson top-50 residual-DE, leave-KO-out | — | — | **+0.078 Rest / +0.035–0.039 Stim** (full); −0.028 (subset) | — | rand −0.10 / deg −0.08 | **know ✅** |
| **Target-ID / virtual-KO screen** | — | — | — | — | — | degree-null | **EXCLUDED** |

### Task 1 — Stim-state classification: raw wins; the encoder does NOT beat raw
raw **0.882** > know 0.846 > **fm_z 0.835** > pca 0.744, null 0.142. At abundant labels the trained
encoder embedding **loses to raw expression** (−0.047) — consistent with the field ("PCA rules them
all") and our session finding that knowledge/encoder help is concentrated in low-data, not here.
→ "best" on this task today = raw head; wire knowledge as an auto-on low-label augmentation (separately
measured +0.14 over raw at ~60 labels).

### Task 2 — Cell-type annotation: the FM encoder is BEST (its genuine edge)
**fm_z 0.536 > pca 0.514 > raw 0.490 > know 0.395**, majority-null 0.017. The frozen encoder beats raw
by **+0.045** and beats PCA by **+0.022** — this is where the trained model earns its place (matches the
session's "annotation +0.039" result). Knowledge-means alone are worst here (mean-pooling discards the
fine cell-type resolution). **Caveat baked into the card:** single donor D534 → not donor-disjoint, so
this is *in-donor* annotation, not cross-donor generalization.

### Task 3 — Unseen-perturbation effect prediction: knowledge wins vs nulls
Knowledge-weighted neighbor-mean beats random-neighbor (−0.028 vs −0.102) and the **degree-matched
null** (−0.077) on the 300-KO subset (`model_beats_nulls=true`); at full scale (33,983 contrasts, ~7k
KOs/context) it is strongly positive — know_r +0.078 Rest, +0.035/+0.039 Stim, know−rand t=+13.7…+28.5
(`docs/20261109_IMMUNE_PERTURBSEQ_KNOWLEDGE_TRANSFER_GATE.md`). A learned linear model (kernel ridge)
did *not* beat the neighbor-mean, so the GPU-GNN bar is "beat the knowledge-neighbor-mean."

### Task 4 — Target-ID / virtual-KO screen (EXCLUDED, documented)
`code_20261004/test_virtual_ko.py` is a **synthetic unit test** (planted effect) requiring torch; no
distinct real-data input. The real measured screen is a gated **leave-KO-out against CZI Perturb-seq** =
Task 3's data; its degree-null is folded into Task 3.

## Verdict — where our model is best, where it is not
- **Annotation / cell-state**: FM encoder is **best** (beats raw + PCA). Genuine model edge — keep and
  strengthen the encoder here.
- **Unseen-perturbation**: knowledge (neighbor-mean) is **best** vs nulls — deployable cheap win.
- **Abundant-label stim classification**: **raw wins**; encoder and knowledge both below → don't ship
  them as default here; use knowledge only in the low-label regime.
- **Stratification / cross-cohort** (not in this harness; needs a batch-clean rep): PCA/signatures win
  today — the batch-leakage fix is the lever to make the model best there.

"Best" is defined operationally: a representation wins a task only if it **beats the task's baseline AND
null** under group-disjoint splits. The scorecard now scores the actual model (fm_z) on every runnable
task, so this is measured, not asserted.

## Data audit (Spark)
- ✅ Task 1/2(annot): `step0/GSE261278_D534.paired.h5ad` (single donor → annotation in-donor only).
- ✅ Task 3: `perturb_full/GWCD4i.DE_stats.h5ad` (33,983) + `fs_long/work/czi_tcell_deltas.npz` (300-KO).
- ✅ fm_z: `fs_long/work/hybrid_model.pt` embedded via envpin2 (torch 2.14.1, CUDA) → `z_fm_stim.npy`.
- ❌ No cross-donor / independent-cohort annotation set → annotation single-donor only.

## Run it
```
# CPU harness (torch-free): writes scorecard.json incrementally
ssh -i ~/.ssh/spark_train_ed25519 yzhang@192.168.1.205
cd /home/yzhang/immune_fm_spark/ws_bench
python3 make_xs.py                                    # xs_stim.npy (system py3, h5py)
PYTHONPATH=../code_20261004:../eval_repair_20261107 ~/ihlm/envpin2/bin/python embed_fmz.py  # z_fm_stim.npy (torch)
python3 -u run_bench.py                               # scorecard.json (all 4 reps)
```
Gotchas baked in: CPU parts torch-free (no scipy.stats); fm_z only in envpin2; robust AnnData column
reader (var `_index` is a nullable-string group); annotation uses `solver='saga'` (lbfgs multinomial on
2000-d was ~28 min and didn't finish — saga finishes in seconds); `pkill -f "[r]un_bench"` bracket-trick
(plain `pkill -f run_bench` matches your own ssh and kills the session).
