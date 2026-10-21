# Innovation thesis — our own cyclic-peptide LLM

**Date:** 2026-10-21 · Scope: the *own* cyclic-peptide generative model (`research/guangzhou_all_atom/cyclic_llm/`), distinct from the adopted-BoltzGen "generate→verify→select" workflow manuscript (`research/guangzhou_all_atom/docs/MANUSCRIPT.md`, which uses BoltzGen **unchanged** and is under MAJOR REVISION per the committee reviews). Written for publication; candor over spin — every number traces to a file or is marked NOT MEASURED.

---

## 0. The honest headline

**We do not currently have a demonstrated cross-target generalization result — and our own data shows the wall.** Cross-target transfer is **NULL** for our own display-conditioned LM and **NEGATIVE** for our BoltzGen fine-tune. What *is* demonstrated is a different, real contribution: an own cyclic-peptide LM **conditioned on mRNA-display NGS enrichment** — a data signal that exists at scale, unlike per-target structural/affinity binder labels — that ranks within-target binders strongly and generates non-canonical (ncAA) chemistry natively. The cross-target claim is the open problem and the closed-loop execution-verified reward is the proposed, **unproven**, route to it.

---

## 1. Measured baseline (what the artifacts actually show)

| Metric | Value | Regime | Source |
|---|---|---|---|
| Model (v2/v3/v3.1) | nanoGPT-style, d_model=256, 6 layers, 8 heads (~few M params); 20-AA char vocab | — | `train_cyclic_llm_v2.py`, `..._v3_1.py` |
| Training signal | display-NGS **enrichment** (log2fc R6/R2), control-token conditioned; PADI4 RaPID ~370k peptides × 5 rounds | — | `train_cyclic_llm_v2.py` |
| Generation validity | 0.998–1.000 | cross-target eval | `results/cyclic_llm_v3_1_FIKK13_eval.json` |
| Novelty fraction | 0.962–1.000 (not memorizing) | cross-target eval | same |
| **Within-target binder ranking (selector)** | **AUC 0.959**; lift top-5% **14.9×**, top-10% 8.5× | within-target, sequence-held-out (PADI4) | `results/cyclic_llm_selector_PADI4_trajtrain.json` |
| **Cross-target transfer (own LM v3.1)** | **NULL** — enrichment-conditioning Δ = 0.034 (hi vs lo), 0.022 (heldout vs trainmean); `target_features_matter: false` | leave-one-target-out (held out FIKK13; train PADI4+hPCSK9) | `results/cyclic_llm_v3_1_FIKK13_eval.json` |
| **Cross-target transfer (BoltzGen fine-tune)** | **NEGATIVE** — mean Δiptm = **−0.16** on held-out targets (per-target −0.079 / −0.093 / −0.308); designability worse | LOTO smoke, 3 targets × 4 designs | `results/boltzgen_loto_smoke_summary.json` |
| Cheap surrogate (predict designability, LOTO) | AUC 0.455 / 0.482 / 0.638 / 0.644 — near-chance to weak | LOTO, 7 targets | `results/speed_surrogate_loto.json` |
| HELM/monomer LM (ncAA-native) | builds; validity/novelty/ncAA-fraction + permeability-conditioning reported as the eval design | single-file | `train_helm_monomer_llm.py` — **exact eval numbers NOT MEASURED here** |

**Reading of the table.** The own model is a *small* LM. It validly and novelly generates. Its one strong, held-out *win* is **within-target** binder ranking from the display signal (AUC 0.96) — explicitly the display-based-binding axis the note says "SOTA defers," **not** cross-target. Every **cross-target** probe we have is NULL or negative. The v3.1 eval itself states: *"If still NULL, the data wall is deeper than target count,"* and flags a chemistry confound (train cyclization co-varies with target).

---

## 2. The defensible kernel (one sentence)

> An own cyclic-peptide generative LM trained on **mRNA-display NGS enrichment** — the binder signal that scales — giving strong *within-target* binder ranking and native ncAA generation, reported alongside a rigorous *negative* result that **cross-target** generalization remains unsolved even with multi-target conditioning and generator fine-tuning.

That is a real, honest contribution. It is **not** "we solved cross-target cyclic design."

## 3. Novelty positioning — new vs prior art

| Component | Status |
|---|---|
| Pocket-conditioned cyclic generation (BoltzGen, RFpeptides) | **Prior art — adopted**, not ours. |
| Monomer/HELM-level peptide LM (HELM-GPT and relatives) | **Prior art in form.** Our `train_helm_monomer_llm.py` is an ncAA-native LM in that family; novelty only if the display/permeability conditioning yields a measured, held-out effect (not yet reported). |
| RLVR / verifiable-reward RL | **Established paradigm.** |
| SDL / DMTA design loops | **Crowded field.** |
| **Display-NGS-enrichment-conditioned generation + selection as the primary binder signal** | **The defensible kernel** — using the data source that actually exists at scale (selection depth) rather than scarce structural labels; the within-target selector (AUC 0.96) is the evidence. |
| **Rigorous cross-target negative (NULL own-LM + regressive FT)** | **A publishable finding**: the cyclic cross-target data wall is deeper than target count, and naive generator fine-tuning *regresses* on unseen targets (Δiptm −0.16). |

We must **not** present the adopted-BoltzGen reranking workflow as the LLM innovation; the committee already flagged that it shows score *disagreement*, not generator superiority.

## 4. Demonstrated vs pending

- **Demonstrated:** within-target display-conditioned binder ranking (AUC 0.96, 15× lift); valid+novel generation; (form of) ncAA-native generation. The honest cross-target negative.
- **Pending / NOT demonstrated:** cross-target generalization; any closed-loop *execution-verified-reward* training actually improving the model (the loop is built-not-fed); the HELM-LM conditioning effect size; any wet-lab validation.

## 5. The one proof experiment that decides the aspirational claim

**Question:** can the closed-cycle *execution-verified physics reward* (MM-GBSA/FEP on real runs) break the cross-target data wall that display-conditioning alone (NULL) and BoltzGen fine-tuning (−0.16) could not?

**Design:** leave-one-target-out across ≥3 (ideally same-chemistry) targets. Train the own/FT model with the closed-loop reward on N−1 targets; generate for the held-out target; score the held-out designs by the **real execution-verified physics** (not the cheap surrogate — it is near-chance). 

**Metrics / controls:**
- Primary: held-out hit-enrichment vs the ~3–8% cross-target SOTA bound.
- Baselines (mandatory): adopted BoltzGen (unchanged), the within-target selector, and random/size-matched selection at equal generation+scoring budget.
- Success = held-out enrichment **above** the SOTA band *and* above adopted-BoltzGen, with uncertainty (per-target, not pooled). Refutation = NULL/negative, which is itself the honest data-wall result to report.

**Cost/gating:** GPU; spot-only; review-before-spend; held guarded until explicit go.

## 6. Threats to the claim (stated up front)

1. **Cross-target is unsolved and our data shows the wall** — NULL (own LM) and NEGATIVE (FT). This is the central risk, not a footnote.
2. **Chemistry confound** — in the only same-platform trio, cyclization co-varies with target (thioether vs photo-crosslink); a positive could be chemistry, not target identity. A clean test needs ≥3 same-chemistry targets (we have 2).
3. **Small models / deep-model skepticism** — related internal work shows deep models not beating simple baselines; our model is a few-M-param LM.
4. **Circularity** — if the reward that *trains* the model is the same physics that *evaluates* it, a "win" can be self-fulfilling. Mitigation: the held-out evaluator must be a modality the training reward did not directly optimize (e.g. train on cofold-geometry reward, evaluate on independent MM-GBSA/FEP or display enrichment), and wet-lab remains the only non-circular endpoint.
5. **Data scarcity** — the signal that scales is display depth, not structural binder labels; the thesis lives or dies on exploiting that.

---

*Artifacts cited are under `research/guangzhou_all_atom/`. The discredited in-distribution decomposition figure is deliberately not used. No training/eval/GPU was run to produce this document.*
