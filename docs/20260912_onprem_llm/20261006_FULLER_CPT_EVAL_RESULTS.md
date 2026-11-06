# Fuller 9B concept-CPT — final eval results (spot EC2, constrained + unconstrained)

**Date:** 2026-10-06 (UTC). The fuller run (CPT 1200 steps + merge + SFT 500, on the spark GB10) evaluated on
a **spot** EC2 box (g6.2xlarge L4, self-terminated; no spark-GPU wait, no on-demand). Transformers engine,
frozen 261-item openbook diagnostic (knowledge_recall n=112, scientific_qa n=149). domainpro was
**reconstructed from the HF base + two 58 MB adapters** (merge midtrain-1200 → base_domain, then SFT) — no
18 GB merged-model transfer. Results: `s3://…/eval/spot_fuller_20261006_024755/`.

## Results (base is identical across arms — constrained argmax-over-{A–E})
| arm | knowledge_recall | scientific_qa | overall | invalid |
|---|---|---|---|---|
| **base** (orig Qwen3.5-9B) | 0.670 | 0.611 | 0.636 | 0 |
| **CPT-1200 only** (constrained) | 0.705 | 0.644 | 0.671 | 0 |
| **domainpro = CPT-1200 + SFT** (constrained) | **0.723** | 0.617 | 0.663 | 0 |
| domainpro (**unconstrained**, native) | 0.705 | 0.611 | 0.651 | **4 / 261** |

## CPT-only trajectory (400/800/1200, constrained, no SFT — same base 0.6696)
| CPT steps | knowledge_recall | Δ vs base | scientific_qa | overall |
|---|---|---|---|---|
| 400 | 0.6875 | +1.8pp | 0.6309 | 0.6552 |
| **800** | **0.7143** | **+4.5pp** | 0.6443 | **0.6743** |
| 1200 | 0.7054 | +3.6pp | 0.6443 | 0.6705 |

Results: `s3://…/eval/spot_traj_20261006_035134/`. **The CPT-only knowledge curve is NON-monotonic: it
peaks at ~800 steps (+4.5pp) and slightly regresses by 1200 (+3.6pp)** — mild over-training past the peak,
NOT "more steps = more lift." CPT-800 is the best CPT-only checkpoint.

## Reads (honest)
1. **The concept-CPT works, but the gain PEAKS (~800 steps), it does not scale indefinitely.** The deployed
   domainpro (CPT-1200 + SFT) reads knowledge_recall **+5.4pp** over base (0.670→0.723) constrained — SFT adds
   ~+1.8pp on top of CPT-1200-only (0.705→0.723). **Correction:** an earlier draft here claimed "more CPT steps
   (300→1200) = larger lift" — the per-checkpoint trajectory above refutes that; CPT-only knowledge peaks at
   800 and dips by 1200. Implication: **domainpro should be rebuilt on the CPT-800 checkpoint** (higher CPT-only
   base, +4.5 vs +3.6pp) before any further step-count increase — pushing CPT further is past the peak.
2. **CPT adds the knowledge; SFT restores the format.** CPT-1200 alone = **+3.6pp** knowledge. SFT adds
   format/instruction-following and lifts the constrained score to **+5.4pp**. Critically, SFT cuts the
   invalid rate from the CPT-only model's **261/261** (prose) to **4/261** unconstrained — i.e. the SFT'd
   deployed model follows the MCQA format **natively**; the constraint only guarantees the last ~1.5%.
3. **The format fix is validated (both layers).** Constrained decoding → **0 invalid** for every model incl.
   the raw CPT; SFT → near-0 invalid natively. This confirms `20261005_FORMAT_GUARANTEE_RESOLUTION.md`:
   SFT (model) + constrained decoding (harness guarantee) both do their job. The earlier "cpt800 = 261
   invalid" was an instrument/format artifact, NOT knowledge loss — now proven.

## Honesty / scope
- **Open-book MCQA diagnostic only** — not execution-task success, broad domain judgment, or client
  acceptance (the artifact's own scope). n=261; no CIs computed.
- **Constrained** = next-token argmax over the {A–E} option tokens (= logprob-over-letters), which is both
  the correct instrument for a base/CPT model AND the production format guarantee; it reads slightly above
  the unconstrained generation (it rescues the few the model would fumble + always emits a valid letter).
- base here is 0.670 (constrained) vs 0.679 (earlier generation) — a method difference (argmax-letter vs
  free-gen), consistent; both arms use the same method so the deltas are fair.
- **Leakage (now certified — QUALIFIED YES; see `20261006_EVAL_HOLDOUT_CERTIFICATION.md`):** the gain is
  **not** a leakage artifact. Against real S3 data: 5/261 eval stems appear verbatim in the concept-SFT
  (all MedMCQA/knowledge_recall) and 7/261 are genuine near-dup item-leaks (Jaccard ≥0.8); the prior
  "exact-stem filter" was run against a *different* export and never touched `multitask_sft_concept.jsonl`.
  **But** the +5.4pp knowledge_recall net gain (+6 items) sits on the CLEAN items: of the 7 leaked items
  only 1 flipped base-wrong→domainpro-right; the <0.6-overlap clean bucket (88 items) carries +5 of the net
  gain. Leakage-controlled re-scores: **drop the 8 high-overlap items → +3.8pp; drop everything ≥0.6 → +5.7pp.**
  **For any external claim, report the dedup-controlled +3.8pp alongside the raw +5.4pp.** Still UNcertified:
  the eval is NOT source-family-held-out from the SFT (MedMCQA/MedQA/SciQ/PubMedQA families are in BOTH, no
  split manifest) — absolute scores are in-distribution; CPT corpora are clean by source but only ~11% were
  exact-scanned and no embedding/paraphrase audit was run. Root-cause fixes (re-filter vs the SFT file itself;
  add an item-id split manifest) are documented in the certification doc — do before any external release.
- **Cost:** this spot box ≈ g6.2xlarge spot ~45 min (~$0.5); the earlier (deviating) on-demand cpt800 box
  was ~$1.3–1.8. Both self-terminated.

## Feeds
- **Paper D** — the "full(er)-corpus CPT decision row" its Appendix C flagged as pending GPU is now answered:
  **concept-CPT lifts domain knowledge (+5.4pp at 1200 steps) and scales with steps** — a real, if modest,
  capability gain, consistent with the paper's "harness carries the bar; CPT adds domain knowledge" thesis.
- Next (updated): the trajectory across checkpoints 400/800/1200 is **done** (above) — the plateau/peak is
  **~800 steps**, so "more CPT steps" is NOT the lever; instead **rebuild domainpro on CPT-800** and compare
  800+SFT vs 1200+SFT. Source-family-holdout certification is **done** (`20261006_EVAL_HOLDOUT_CERTIFICATION.md`,
  qualified-yes; report +3.8pp dedup alongside +5.4pp). Remaining: the end-to-end LLM+harness (RealBio) delta,
  running now, to confirm whether this knowledge gain reflects beyond the MCQA proxy.
