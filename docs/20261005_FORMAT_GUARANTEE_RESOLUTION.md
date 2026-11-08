# Output-format reliability — the production resolution (harness-enforced, model-agnostic)

**Date:** 2026-10-06 (UTC). Trigger: the CPT-only checkpoint-800 emitted prose instead of a letter
(`docs/20261005_SPOT_CPT800_EVAL.md`), and — correctly — "a model that free-generates where a structured
answer is required is not useful in a real product." This is the resolution.

## Principle: format is a HARNESS guarantee, not a model hope
Never rely on the raw LLM to free-generate valid structured output. Enforce it at the serving/decoding
layer so an invalid output is **impossible** for ANY model (base, CPT-only, or SFT). This is also exactly
CLAUDE.md's "validate all values against schema allowed_values" guardrail, extended to decoding.

| Output kind (BioMate task) | Enforcement | How |
|---|---|---|
| **enum / choice** (routing = pick a workflow from the candidate list; classification; MCQA) | **constrained decoding to the allowed set** | vLLM `guided_choice` (serving) / constrain next-token to the option tokens (**implemented now** in `spot_cpt800_worker.py --constrain`) |
| **structured** (param extraction, tool/function calls, JSON) | **guided-JSON against the schema** + validate | vLLM `guided_json`/`guided_grammar` (serving); Node harness validates + drops/normalizes per `allowed_values` (already the rule+validation guardrail) |
| **format/regex** (IDs, accessions) | guided_regex / rule normalization | vLLM `guided_regex` + the rule layer |
| **freeform** (findings narrative) | no constraint; validate downstream | — |

**Why this makes the on-prem small model product-viable:** most tasks that matter are S/R/V (selection/
rule/verifier) — routing picks from a retrieved list, params fill a schema, tool-calls are structured. If
the harness constrains + validates these, a smaller model with weaker raw instruction-following is still
**format-safe in production** — the harness carries format the same way it carries selection. This is the
same thesis as `20261004_PAPER_B_HARNESS_VS_LLM_DRAFT.md`.

## Two layers, both needed (not either/or)
1. **Decoding/validation (harness) — the GUARANTEE, ships now, model-agnostic.** Constrained/guided decoding
   + schema validation. An invalid enum/JSON cannot be emitted. Works even on a base/CPT checkpoint.
2. **SFT (model) — the REINFORCEMENT.** SFT teaches concise in-format answers so the *unconstrained* path is
   also well-behaved and the constrained path rarely has to override. Evidence it works: the bounded
   CPT+**SFT** "domainpro" had **0 invalid** (followed format); only the CPT-**only** intermediate failed.

## Concrete actions
- ✅ **Eval:** `--constrain` added to the eval worker (option-letter forward-pass argmax) → 0 invalid for
  any model, and it doubles as the logprob-over-letters instrument for CPT-only checkpoints (`8afd50531`).
- **Serving (when the domainpro is served via vLLM):** turn on guided decoding — `guided_choice` for
  routing/classification, `guided_json` (the workflow param schema) for param/tool-call extraction. Set it
  in the vLLM OpenAI request (`extra_body={"guided_choice":[...]}` / `{"guided_json":<schema>}`).
- **Node harness:** confirm routing/param/tool-call paths already pass candidate lists / schemas and
  **validate** before use (the S/R/V guardrail) — so the format guarantee holds regardless of the model tier.
- **SFT data:** ensure the SFT set enforces the exact required output format (concise, in-schema) so the
  unconstrained path is clean too.
- **Benchmarks/evals:** run constrained (enum tasks) so "invalid" reflects the *product* path, not a raw-gen
  artifact; keep an unconstrained run as a diagnostic of the model's native format adherence.

## Next verification
When spark's CPT→merge→SFT finishes (~soon), eval the **domainpro** both ways: unconstrained (expect ~0
invalid — SFT works) and `--constrain` (guaranteed 0 invalid) → the real knowledge delta vs base 0.679.
Also re-score CPT-only checkpoint-800 with `--constrain` to show the knowledge was there all along
(not lost), proving the 261-invalid was a decoding-layer gap.
