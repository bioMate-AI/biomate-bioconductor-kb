# Routing SFT — first VALID 2×2 eval (round 1)

Base: Qwen ~27B (natively multimodal), text path. Adapter: routing QLoRA r=16, 220 steps,
train_loss 0.016, on 1,400 examples (417 audited-generated + 1,244 real GEO). Held-out: 200
RealBio routing items. Eval via transformers + `disable_adapter()` (base vs SFT), identical
scoring to `routing_eval.py`. Supersedes the flawed prior run (delta 0.0).

## Result (accuracy)
|            | starved (no candidates) | in-format (candidates) |
|------------|-------------------------|------------------------|
| base       | 0.13                    | **0.96**               |
| SFT        | 0.06                    | **0.99**               |

- **Candidate/retrieval effect** (base_informat − base_starved): **+0.83** CI95 [0.78, 0.88].
- **True SFT lift** (sft_informat − base_informat): **+0.03** CI95 [0.005, 0.06] — small, significant.
- SFT fixed 7 hard same-domain confusions (e.g. base→`sopa`/`freyja`, SFT→`nf-core/sarek`).
- `sft_starved` dropped 0.13→0.06: training to select-from-candidates narrowed free-form recall
  (emits descriptive names instead of canonical). Operationally harmless; a mixture caution.

## Conclusions
1. The 2×2 design works; the old eval was confounded. Results verified against raw outputs (not
   substring-inflated).
2. Base + retrieval already solves routing (96%). SFT adds a small, real gain on confusable cases.
3. **Fine-tuning budget should target weak-base tasks** (param extraction, autofix, output
   interpretation, restraint), not routing — routing stays low-weight in the joint mixture.
4. Joint multi-task training must include free-form/no-candidate examples to avoid narrowing.

Artifacts: adapter + result in
s3://biomate-models-399683337364/biomate-core-local-trial/20260912/sft_routing_20260915/
