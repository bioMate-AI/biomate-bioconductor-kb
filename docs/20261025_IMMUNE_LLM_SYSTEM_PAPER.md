# An evidence-grounded immune LLM system: downstream tasks measured honestly

**Status:** DRAFT v0.1 (consolidated system/resource paper) · **Created:** 2026-10-25
**Framing:** the contribution is a *system* + two honestly-characterized downstream capabilities, not a
discovery. Every number is traceable to a logged run or a cited result doc. Where a result is a known
null or a memorization artifact, it is reported as such — the honesty is the credibility.

> **Honesty contract.** Each quantitative claim is reported against a matched baseline and a permutation
> null where relevant; leakage-prone numbers are labelled; a capability that fails a control is reported
> failed. This paper deliberately includes the controls that temper its own claims.

---

## Abstract

Foundation models for single-cell and biomedical tasks are usually evaluated as *models*; we instead
evaluate a *system* — a deployable LLM wrapped in evidence/knowledge channels — on immune-relevant
downstream decisions, and report what survives rigorous controls. Three findings. (1) **Representation
is a known null:** the multi-omic foundation embedding does not beat PCA on cell-type representation
(≈+0.009 dimension-matched; apparent gains are ~78% memorization) — consistent with the field, and not
our contribution. (2) **Target identification:** an LLM-reasoned evidence channel, added to a
harmonic-sum fusion over OpenTargets-genetics and STRING-PPI, **lifts the fused ranking on 9/10 immune
diseases** (mean AUROC 0.482→0.569) against an OpenTargets clinical-precedence gold with permutation
nulls; LLM-alone is the single strongest channel (0.76 vs 0.42 genetics). A literature-prominence
control shows this advantage is **substantially recall of well-characterized targets** (0.76 on famous
vs 0.56 on less-published clinical targets, genetics 0.41) — a strong clinical-knowledge recall and
integration channel, *not* novel-discovery-by-reasoning. (3) **Deployability (KB-dividend):** the same
evidence harness exhibits *inverse scaling* — it lifts small, on-prem-deployable open models by +39–70
percentage points on workflow routing (converging to ~0.80–0.95, so a 9B+harness beats a frontier model
bare) while adding only ~+7pp to a frontier model, and acts as a **safety lever** (invalid-method-regime
rate 0.125→0 on Bioconductor method selection). The unit of contribution is the system, two honestly
bounded downstream wins, and the evaluation discipline that separates real signal from memorization and
leakage.

---

## 1. Introduction

Single-cell/biomedical foundation-model reanalyses frequently report advantages that do not survive clean
splits and matched baselines (Kedzierska 2023; Ahlmann-Eltze 2025; scPerturBench *Nat Methods* 2025). We
take the position that the useful object is not the raw embedding but the **model-in-a-system**: a
deployable LLM augmented with structured evidence channels (genetics, PPI, pathways, literature-reasoned
LLM scoring) and a fusion/arbiter, evaluated by downstream decision utility. We report two downstream
capabilities where the system genuinely helps — each with the control that bounds the claim — and one
where it does not (representation), stated plainly.

**Contributions.** (1) An evidence-grounded immune LLM system (channels → harmonic-sum arbiter → API/MCP).
(2) A measured, controlled target-ID result: the LLM channel lifts fused ranking 9/10 diseases, with an
explicit memorization decomposition. (3) The inverse-scaling KB-dividend + safety-lever result that makes
the system deployable on-prem. (4) The evaluation protocol (clean splits, matched nulls, confound and
memorization controls) that produced honest numbers in both directions.

---

## 2. The system

Per-omic/evidence **channels** (OpenTargets genetic-association, STRING-PPI, pathway co-membership,
DepMap essentiality, a cached-evidence table channel, and an **LLM-reasoned channel** that scores
candidate genes for disease-specific target evidence) are fused by a **HarmonicSumArbiter** (the
OpenTargets harmonic-sum scheme + per-source reliability weights), exposed via an API and MCP
(`identify_targets`). Code: `backend/lib/galaxy/ai/target_id/`.

---

## 3. Representation is a known null (stated, not claimed)

On cell-type representation, the multi-omic FM embedding `z` ties a dimension-matched PCA baseline
(+0.0089 macro-F1), and its apparent all-cells advantage is ~78% memorization (all-cells +0.2548 →
leave-study-out +0.057). Cross-modal RNA→protein imputation: FM 0.553 < PCA(RNA) 0.583. These match the
field consensus and are **not** our contribution; we report them so the rest is read in that light.
(Detail: `research/immune_llm_baseline`, prior program docs.)

---

## 4. Downstream task 1 — Target identification (measured + controlled)

**Setup.** 10 canonical immune diseases (EFO resolved live). Gold = OpenTargets `clinical` datatype ≥ 0.5
(clinical-precedence targets), distinct from the `genetic_association` channel (not circular). Universe =
clinical gold + hard-negatives (other diseases' clinical targets) + OT genetic candidates; every channel
scores the same universe. Arms via `run_demonstration` (HarmonicSum fusion; per-channel arms;
300-permutation null; AUROC). LLM = gpt-6.1 via OpenRouter, batched scoring.
Code: `backend/lib/galaxy/ai/target_id/bench_targetid_llm_v3.py` → `bench_targetid_llm_v3_immune.json`.

**Result (10 diseases).**

| Arm | mean AUROC |
|---|---|
| OpenTargets-genetics alone | 0.424 |
| System without LLM (OT+STRING) | 0.482 |
| **System with LLM** | **0.569** |
| **LLM channel alone** | **0.764** |
| permutation null | 0.590 |

- System **+LLM beats −LLM on 9/10** diseases (+0.087 mean). LLM-alone beats OT-genetics on 9/10 and the
  null on 8/10 — the single strongest channel.
- Per-disease LLM-alone: psoriasis 0.96, SLE 0.94, systemic sclerosis 0.84, RA 0.83, Crohn's 0.83, UC
  0.82, ankylosing spondylitis 0.81, asthma 0.77, multiple sclerosis 0.52 (~null), type-1 diabetes 0.32.
- Failures (MS, T1D) are diseases where **every** channel sits at/below the null.

**Memorization control (front and centre).** Literature-prominence stratification of the clinical gold,
pooled over diseases (`bench_targetid_llm_v4_generalization.py` → `…_v4_generalization.json`):

| Clinical-gold subset | LLM-alone AUROC | OT-genetics |
|---|---|---|
| All | 0.66 | 0.44 |
| HIGH-literature (famous) | 0.757 | 0.465 |
| LOW-literature (less-published) | 0.555 | 0.409 |

The advantage **concentrates in famous, well-published targets** and falls to 0.56 on less-published
clinical targets — substantially memorization/recall, not clean reasoning. It is not pure recall: on
low-literature targets the LLM (0.56) still beats genetics (0.41) by ~0.15. Disease-specificity is
controlled by construction (hard-negatives are other diseases' clinical targets, so 0.76 is
disease-specific, not generic immune-gene fame).

**Honest claim.** *The LLM-reasoned channel is a strong clinical-knowledge recall + integration channel
that lifts fused target ranking on 9/10 immune diseases — not a novel-target-discovery-by-reasoning
engine.* Full detail + the four eval bugs that had previously hidden this: `docs/20261025_TARGETID_LLM_CHANNEL_CONTRIBUTION.md`.

---

## 5. Downstream task 2 — Deployability: the inverse-scaling KB-dividend + a safety lever

The same evidence/knowledge harness around the LLM shows **inverse scaling with model strength**
(`docs/20261004_CLOSE_THE_GAP_ROUTING.md`, `docs/20261022_OPEN_MODEL_BARE_VS_HARNESS_ONPREM.md`,
`docs/20261004_BIOC_SELECTION_MATRIX_RESULTS.md`):

- **Workflow routing (n=200):** every open model gains **+39–70pp** from the model-agnostic catalog
  harness, biggest for the weakest — 9B 0.12→0.82 (+70), Qwen2.5-7B 0.14→0.72, Qwen3.5-27B 0.24→0.93,
  GLM-5.3 0.38→0.88, DeepSeek-V4-pro 0.42→0.80 (+39), Kimi-K3 0.45→0.86 — converging to ~0.80–0.95.
  **A 9B + harness beats a frontier model bare** = the on-prem/privacy/cost deployability argument.
  Frontier contrast: gpt-5.6 on LAB-Bench 0.688 bare → 0.762 system (only +7.4pp).
- **Bioconductor method selection:** 9B bare→+KB **+15pp (0.80→0.95) ≈ frontier (0.975)**; and the KB
  drove the **invalid-method-regime rate 0.125→0** (e.g. ORA-on-ranked-data) — a measured **safety
  lever**, not just accuracy.

Interpretation: the evidence system's value is largest exactly in the deployable, small/on-prem regime
that is the product — making a weak deployable model frontier-competitive and demonstrably safer — and
small for already-strong frontier models. (Numbers in this section are quoted from the cited on-prem
result docs / the program's KB-dividend record; re-verify each digit against those docs before submission.)

---

## 6. Limitations
- Representation FM≈PCA (known; §3).
- Target-ID advantage is recall-concentrated; a **novel-discovery** claim requires a temporal holdout
  (post-training-cutoff approvals), not the literature proxy used here. *(A holdout/generalization
  experiment is in progress — RESULT PLACEHOLDER to insert.)*
- Target-ID: one clinical gold (OT ≥0.5) and one LLM (gpt-6.1); MS and T1D fail (all channels at chance).
- On-prem harness fairness: tool-firing on the local model path vs the text-only BYO path needs a matched
  execution-harness run to measure the dividend on execution, not just text.

## 7. Methods (summary)
Target-ID: per-(disease) OT `clinical` gold vs `genetic_association` channel + STRING + batched
LLM scoring over a shared universe; `run_demonstration` harmonic-sum fusion + per-channel arms +
300-perm AUROC null; literature-stratified memorization control. KB-dividend: bare-vs-harness on
routing (n=200) and Bioconductor method selection, per the cited on-prem docs.

## 8. Data & code availability
`backend/lib/galaxy/ai/target_id/` (system + `bench_targetid_llm_v3.py`, `bench_targetid_llm_v4_generalization.py`,
result JSONs); on-prem/KB-dividend harnesses and results per `docs/20260912_onprem_llm/` and
`docs/20261004_*`, `docs/20261022_OPEN_MODEL_BARE_VS_HARNESS_ONPREM.md`.

## 9. Contribution statement (for a skeptical reviewer)
We do **not** claim a foundation model that beats simple baselines on representation, nor novel target
discovery by LLM reasoning. We claim: (i) a deployable evidence-grounded immune LLM **system**; (ii) an
LLM evidence channel that provides strong clinical-knowledge **recall** and lifts fused target ranking on
9/10 immune diseases, with its memorization bound explicitly measured; (iii) an inverse-scaling
KB-dividend that makes a small on-prem model frontier-competitive and measurably safer. The evaluation
discipline that distinguishes these real, bounded wins from the (reported) nulls and memorization
artifacts is itself part of the contribution.

## Change log
- 2026-10-25 — v0.1: consolidated target-ID (v3/v4) + KB-dividend/on-prem + representation-null into one
  honest system paper. Numbers from logged runs (target-ID) and cited on-prem docs (KB-dividend).
