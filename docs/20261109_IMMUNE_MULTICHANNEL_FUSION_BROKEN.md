# Multi-channel evidence: the signal is strong, but the FM's learned fusion is BROKEN

Recorded: 2026-11-09. Prompted by the correct critique that every prior eval was single-channel
(RNA-only) — the FM is designed for multi-channel fusion, and a single-channel baseline is unbeatable
on a single channel. GSE261278 D534 is paired CITE-seq: RNA (23,266 genes) + **protein (144 ADTs)**,
which I had been ignoring. The checkpoint is 6-channel (rna/knowledge/tcr/protein/atac/genetics).

## Setup

Stim-state classification (flu/sars vs unstim), cell-type-holdout folds, 3 seeds, fixed C=0.01, across
label budgets. Representations: rna_raw (corpus-scaled HVG 2000), prot_raw (144 ADT, CLR), concat_raw
(naive [RNA,protein]), fm_rna (FM encoder RNA-only, 512-d), **fm_multi (FM encoder RNA+protein fusion,
512-d)**. Protein→checkpoint mapped 29/35 slots via panel_overlap.json + CLR. FM embeddings computed in
envpin2 (real torch/CUDA); protein encoder verified loaded (`omic.enc.protein.*`; the 2 missing keys are
benign aux buffers `gc_centroids`/`gc_counts`). `docs/20261109_multichannel/`.

## Result — AUPRC (mean / 3 seeds)

| budget | rna_raw | prot_raw | concat_raw | fm_rna | **fm_multi** |
|---:|---:|---:|---:|---:|---:|
| ~1000 | 0.882 | **0.931** | 0.918 | 0.835 | **0.692** |
| ~250 | 0.765 | **0.867** | 0.806 | 0.674 | **0.660** |
| ~60 | 0.757 | 0.703 | **0.792** | 0.705 | **0.418** |

## Findings

1. **Multi-channel evidence is real and strong — I was wrong to ignore it.** Protein ALONE (0.931) is
   the single best representation at abundant/mid labels, far beating RNA (0.882). For a stimulation
   task, surface activation markers carry more signal than the 2000-HVG transcriptome. Testing RNA-only
   structurally under-measured the problem.
2. **Naive concatenation works** (concat_raw 0.918; best at the scarce budget 0.792). Simply stacking
   raw channels is a strong multi-channel baseline.
3. **The FM's LEARNED fusion is BROKEN.** `fm_multi` (0.692/0.660/0.418) is dramatically WORSE than
   naive concat, worse than fm_rna (RNA-only FM), and worse than any single raw channel. Adding protein
   *through the FM encoder* actively corrupts the representation (fm_rna 0.835 → fm_multi 0.692 at full;
   0.705 → 0.418 scarce). The protein encoder loaded correctly, so this is a real degradation, not a
   load bug.

## Honest conclusion

Considering multi-channel evidence does **not** rescue the FM — it exposes the opposite. The FM's core
value proposition (learned cross-modal fusion) **fails badly**: a dumb concatenation of raw channels
beats the FM's fusion by ~0.23 AUPRC, and single-channel protein beats everything the FM produces. This
matches the program history (memory `project_immune_llm_code_audit`: "multi-omic fusion ≤ null;
cross-modal linear ridge > deep; protein redundant/undertrained"). The multi-omic channels were never
well-wired during pretraining, so fusing them injects noise.

**Deployable best for multi-channel stim = protein-alone or naive concat, NOT the FM.** If the FM is to
earn its multi-channel keep, the protein/cross-modal fusion path needs repair (retrain the omic encoders
on paired data, or adopt masked-decoder fusion) — and it must be shown to beat naive concatenation
(0.918), not just RNA. Until then, the honest routing system uses raw channels, concatenated.

---

## Addendum — fusion-repair gate: NO fusion headroom (don't repair)

Before scoping an FM fusion-repair, tested whether *any* learned fusion beats naive concat / best single
channel (`fusion_headroom.json`): a nonlinear MLP on concat(RNA,protein) vs logistic-concat vs
protein-alone. Result — MLP fusion is far WORSE at every budget (1000: 0.737 vs concat 0.918 vs protein
0.931; 60: 0.409 vs 0.793). **No fusion headroom.** Learned/nonlinear fusion (the FM's OR a fresh MLP)
loses to linear concat and the dominant single channel. On this task one channel (protein) dominates, so
there is little complementary signal to fuse and nonlinear fusion only overfits. **Verdict: the FM
fusion-repair is NOT justified here — the ceiling is protein-alone (abundant) / linear-concat (scarce).**
A fusion-repair would only be worth testing on a task with genuinely COMPLEMENTARY channels (neither
dominant), which this stim task is not.
