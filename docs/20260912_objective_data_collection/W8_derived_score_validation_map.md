# W8 — Derived-score → validation-dataset map

Synthesis of W1–W7. The canonical FM emits **derived application scores** (OBJECTIVES §3.2),
not clinical heads. Each score's validation dataset + remaining gap:

| Derived score (§3.2) | Produced from | Validation dataset (what we now hold) | Gap to actually run the validation |
|---|---|---|---|
| **Target durability** | FM mechanism + cell-state under inflammation | W4 withdrawal survival: 4 studies, 341 subj / 87 events (iWITH, MG, psoriasis, LN) | disease-heterogeneous; pooling is a hypothesis; needs a working durability read-out first; molecular-paired-N ≈ 0 → validate score-vs-outcome at cohort level only |
| **Neo-presentation risk (irAE)** | H4 presentation delta across HLA | W3 safety AEs (248 baseline pairs, 94 severe) — but generic AE ≠ irAE | need checkpoint-inhibitor irAE cohorts with HLA + peptide; NOT held; H4 works on 1 HLA only |
| **Inflammation-conditional epitopes (tolerance)** | H4 conditioned on inflamed vs resting state | IFN-γ immunopeptidome kill-test (held) + autoimmune taper cohorts (W4) | H4 single-HLA; tolerance-outcome link is indirect |
| **Causal epitope ranking** | causal head (Δz IRM) + H4 | perturbation-KO immunopeptidome (W7: PXD056426 held, ~29 public) | held = 1–2 sets, single HLA; needs the fetchable KO backlog |

## Bottom line
Every derived score has *some* validation data now, but each validation is currently
**cohort-level / single-HLA / small** — enough for directional sanity checks, not for a
generalization claim. The validation sets (vaccine 2,125 · safety 248 · duration 341) are
**VALIDATION only**, never FM training (confirms the non-goal). The gating dependency is
the same for scores and heads alike: **paired, multi-HLA mechanistic data (W7)**.
