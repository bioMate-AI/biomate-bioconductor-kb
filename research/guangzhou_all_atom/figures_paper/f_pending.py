"""Placeholders for figures whose results do not exist yet. They are rendered with a PENDING watermark and name the artifact they wait for;
they never contain numbers. Re-running this file after the artifacts exist should be replaced by the real script (see FIGURES_STATUS)."""
from common import pending_figure

pending_figure("F4_learning_curves", "F4. Learning curves: held-out ranking and yield vs revealed labels",
               "per-round L7 results for the atom LM, ChemBERTa, IH-LM ladder and larger pretrained peptide/chemistry LMs (loop_retro/results/l7_aggregate.json has GBM only; per-round curves not exported)",
               "line plot with bootstrap bands, 0/25/50/100…600 labels, zero-fit and frozen references")
pending_figure("F6_stereo_ranking", "F6. Stereoisomer-resolved within-group ranking (E_f)",
               "L7 E_f logs for IH-LM and larger models (one revealed/target split per group); v4_eval seed-0 reference is a single seed",
               "final-round dot-interval: blind GBM (0 by construction), revealed-mean reference, chirality-aware GBM, IH-LM, larger LMs; n groups in caption")
pending_figure("F7_low_data_sources", "F7. Per-source learning curves for low-data sources (E_s)",
               "L7 per-source logs (sources < 400 peptides, e.g. Faris, Bhardwaj) for all comparators",
               "small multiples, same y-scale, n peptides per facet")
pending_figure("F10_cost_performance", "F10. Cost–performance: parameters and GPU-hours vs yield",
               "L7 per-arm parameters, fine-tune steps, wall-clock and GPU-hours for the IH-LM and larger models; non-inferiority margin line at 0.90 × strongest larger model",
               "scatter with intervals, log axes, no currency conversion in the primary figure")
pending_figure("F12_corpus_overlap", "F12. Corpus overlap / memorisation check for larger pretrained models",
               "per-model pretraining-corpus overlap table and SMILES-prefix completion probes (not yet run)",
               "paired dot plot per model with 95% CI of the real-vs-stereo-scrambled difference")
pending_figure("F11b_kb_matrix", "F11b. Knowledge base × property × substructure-level matrix",
               "a machine-readable export of the property × substructure matrix (currently only in docs/20261029_KB_AUDIT_AND_GAPS.md as text)",
               "tile matrix with counts; count-level vs positional/stereo-level")
