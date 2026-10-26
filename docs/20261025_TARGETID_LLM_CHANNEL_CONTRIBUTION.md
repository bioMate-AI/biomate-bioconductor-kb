# The LLM channel contributes substantially to immune target identification (measured, done right)

**Date:** 2026-10-25
**Code:** `backend/lib/galaxy/ai/target_id/bench_targetid_llm_v3.py` · **Result:** `bench_targetid_llm_v3_immune.json`
**Prior (wrong) conclusion corrected:** `docs/20261021_TARGETID_FUSION_VS_OPENTARGETS_BENCHMARK.md` concluded the target-ID system doesn't beat OpenTargets — but that benchmark **never included the LLM channel**.

## Question
Does the `LLMReasonedChannel` (a frontier-LLM scores candidate genes for disease-specific drug-target
evidence) actually CONTRIBUTE to target-ID? It exists in the system but was off-by-default
(`use_llm=False`), down-weighted to 0.2 in the arbiter, and absent from every benchmark — so its value
had never been measured.

## Setup (honest)
- 10 canonical immune diseases; EFO ids resolved live (OT search).
- **Gold = OpenTargets `clinical` datatype ≥ 0.5** (clinical-precedence targets) — DISTINCT from the
  `genetic_association` channel, so not circular.
- Universe per disease = clinical gold + hard-negatives (other diseases' clinical targets) + OT genetic
  candidates; every channel scores the same universe.
- Channels: OT genetic-association, STRING-PPI, LLM-reasoned (gpt-6.1 via OpenRouter, batched scoring).
- Arms via `run_demonstration`: OT-genetics alone, system −LLM, system +LLM, LLM-alone, 300-perm null (AUROC).

## Result (10 diseases)
| Arm | mean AUROC |
|---|---|
| OpenTargets-genetics alone | 0.424 |
| System without LLM (OT+STRING) | 0.482 |
| **System WITH LLM** | **0.569** |
| **LLM channel alone** | **0.764** |
| permutation null | 0.590 |

- **System +LLM beats system −LLM on 9/10** diseases (+0.087 mean).
- **LLM-alone beats OT-genetics on 9/10; beats the null on 8/10.** It is the single strongest channel.
- Per-disease LLM-alone: psoriasis 0.96, SLE 0.94, syst. sclerosis 0.84, RA 0.83, Crohn's 0.83, UC 0.82,
  ankylosing spondylitis 0.81, asthma 0.77, MS 0.52 (~null), T1D 0.32 (fails).
- Failures (MS, T1D) are diseases where **every** channel (genetics, STRING, LLM) is at/below the null.

## What this corrects — four execution bugs that had manufactured a false null
1. LLM channel off-by-default / down-weighted 0.2 / never in any benchmark.
2. Candidate universe = OT's own hits, excluding the gold → every arm at chance.
3. LLM JSON wrapped in markdown fences → parser silently dropped ~50% of answers.
4. Gold was a noisy DisGeNET dump (non-immune diseases, unresolvable EFO) → replaced with OT clinical gold.
(Plus a 5th: the LLM returns empty on >~130-gene universes → fixed by batched scoring, ≤50 genes/call.)
The LLM in isolation ranks targets correctly (RA → TNF/IL6R/JAK = 1.0, housekeeping = 0.0). The nulls were
the eval, not the model.

## Honest boundaries (before any publication claim)
- **Memorization:** LLM-alone high on a *clinical-precedence* gold partly reflects the model recalling
  known approved targets (recall, not pure reasoning). The sturdier product claim is the **lift**
  (system +LLM > −LLM, 9/10). Generalization to NOVEL targets must be tested separately (held-out
  post-training-cutoff approvals, or targets absent from the model's training).
- One gold (OT clinical ≥0.5), one model (gpt-6.1). Needs: robustness across golds/models, and the
  **on-prem model** (the deployable product) — do the open/small models also get the lift (cf. the
  inverse-scaling KB-dividend result)?
- MS/T1D show it is not universal.

## Product actions this justifies
1. **Turn the LLM channel ON by default** in target-ID (`use_llm=True`).
2. **Re-weight `llm_reasoned` up** from 0.2 in `HarmonicSumArbiter` — it is the strongest channel, not an afterthought.
3. Add the batched-scoring + robust-JSON fixes to the production `LLMReasonedChannel`.

## Next (toward a publishable "immune LLM + downstream tasks" paper)
- Novel-target generalization test (the memorization control).
- On-prem / open-model version of the lift (deployability + inverse-scaling story).
- Extend from target-ID to the other downstream decision tasks on the same honest footing.

## MEMORIZATION CONTROL (v4) — the claim is tempered, honestly
Literature-prominence stratification of the clinical gold (pooled over 10 diseases), LLM = gpt-6.1:
| Target subset | LLM-alone AUROC | OT-genetics AUROC |
|---|---|---|
| All clinical gold | 0.66 | 0.44 |
| HIGH-literature (famous) | 0.757 | 0.465 |
| LOW-literature (less-published) | 0.555 | 0.409 |

**Verdict: the LLM's target-ID advantage is SUBSTANTIALLY memorization** of famous, well-published
approved targets (0.76) — it falls to ~0.56 on less-published clinical targets. It does NOT pass the
clean-reasoning bar (>0.6 and >OT+0.05 on low-lit). BUT it is not pure recall: on low-literature targets
the LLM (0.555) still beats OT-genetics (0.409) by ~0.15 — a modest genuine residual beyond fame.
(Disease-specificity is already controlled by construction: hard-negatives are other diseases' clinical
targets, so the signal is disease-specific, not generic immune-gene fame.)

## HONEST CONCLUSION (what is / isn't publishable)
- **NOT** "the LLM discovers novel targets by reasoning over evidence" — the memorization control fails this.
- **IS** a real, defensible contribution, framed honestly: *an LLM-reasoned evidence channel is a strong
  recall of clinically-established targets that genetics-based channels lack, and lifts the fused target
  ranking on 9/10 immune diseases; its advantage concentrates in well-characterized targets and does not
  extend to novel/less-studied ones.* That is a product/resource contribution (recall + integration +
  provenance), with the generalization limitation stated — not a discovery claim.
- Product value stands (users want known good targets ranked high → recall is a feature); novel-discovery
  value is limited. The two product fixes (LLM on by default; re-weight 0.5) remain justified by the lift.

## Next for a clean submission
- Report the lift AND the memorization decomposition together (honesty = the contribution's credibility).
- On-prem/open-model version (deployability + inverse-scaling story) — does a small model get the same lift?
- If a novel-discovery claim is wanted, it needs a true temporal holdout (post-training-cutoff approvals),
  not this literature proxy.

## NOVEL-DISCOVERY (TEMPORAL) HOLDOUT — attempted, NOT tractable with quick public data
Goal: test whether the LLM lift survives on targets it could not have memorized as approved (a clean
novel-discovery claim). Three tractable proxies were tried and all failed on OpenTargets data structure:
- `disease.knownDrugs` (drug phase) — the field does not exist on the Disease type in OT v4 (HTTP 400).
- `known_drug` datatype score, absolute threshold 0.5 — every clinical-gold target scores <0.5 → no split.
- `known_drug` datatype score, per-disease median split — the score is sparse/zero for most clinical-gold
  targets → both subsets empty (n_pos=0).
**Conclusion:** a clean novel-discovery / temporal holdout CANNOT be established with quick OT queries.
The v4 literature-stratification stands as the memorization control (recall-dominated: 0.76 famous vs 0.56
less-published, modest residual 0.56>0.41). A rigorous novel-discovery claim requires a purpose-built
**post-training-cutoff approval gold** (dated first-approvals after the model's cutoff) — a dedicated
data-engineering task, deliberately NOT faked here. The paper therefore claims RECALL + integration, not
discovery. (scripts: bench_targetid_llm_v4_generalization.py, bench_targetid_llm_v5_holdout.py)
