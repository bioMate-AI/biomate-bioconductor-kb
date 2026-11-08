# Clean-data SFT (sft_sftclean) eval verdict — honest NEGATIVE

**Date:** 2026-10-24 · Eval: `run_eval_sftv3real.sh ADAPTER_TAG=_sftclean` (base vs base+adapter,
out-of-generator held-outs). The payoff gate for the audit-first clean-data effort.

## Result — the SFT REGRESSED the model

| Held-out | base (+harness) | sft_sftclean | verdict |
|---|---|---|---|
| cross_domain_routing | 0.885 | **0.53** | big regression |
| param_prefill F1 | 0.628 (P 0.82 / R 0.51) | 0.547 (P 0.60 / R 0.50) | regression (precision ↓) |
| decomposition_real node_F1 | 0.016 | 0.026 | ~flat |
| decomposition_real structure_acc | 0.368 | 0.059 | collapsed |

## Why (honest diagnosis)
The data was committee-clean (routing realism 0.80, 0% leak), but the **SFT condition mismatched
deployment**:
- The SFT trained on **bare query → gold filename** (no retrieved-catalog context). Deployment /
  the eval scores **query + retrieved catalog → filename** (base+harness already = 0.885).
- So the adapter taught a format that does NOT compose with the harness/catalog, degrading routing
  0.885 → 0.53, and over-writing general param/decomposition behavior (catastrophic forgetting on a
  narrow format).

## Lesson (consistent with the whole program)
- **The harness/retrieval is the lever, not naive SFT.** base+harness routes at 0.885; SFT on bare
  query→filename can't beat that and here actively hurt — the KB-dividend / "model is a component"
  thesis, reconfirmed.
- **Clean data ≠ a good SFT** if the training condition ≠ the deployment condition.

## Actions
1. **Do NOT deploy `sft_sftclean`** — it is worse than base+harness.
2. **DPO (Arm A) should NOT start from `sft_sftclean`** (regressed policy). Start from base or
   `sft_gold`, or reconsider.
3. If SFT is pursued at all, train on the **deployment condition** (query + retrieved candidate
   catalog → gold) so it composes with the harness, not bare query→filename. And guard against
   forgetting (mix general tasks / lower LR / fewer steps).
4. Highest-ROI remains the **harness** (the proven 0.885) + the verified run_code fix — not model SFT.
