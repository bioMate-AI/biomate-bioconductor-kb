# Decisive test: does the fuller-CPT domainpro +5.4pp knowledge gain reflect in the end-to-end LLM+HARNESS (RealBio) metric?

**Date:** 2026-10-06
**Author:** Yaoyun Zhang (automated eval)
**Question:** The fuller concept-CPT `domainpro` (base + midtrain cpt1200 merged + SFT) showed **+5.4pp**
on the knowledge-recall MCQA *slice* (base 0.679 → domainpro 0.723, per the 2026-10-05 bounded run).
Does that gain carry into the **end-to-end RealBio harness** metric produced by
`evaluation/datasets/public_export/run_baseline.py` + `score.py`, and if so **where**?

**Hypothesis (from the task-split):** the knowledge gain should move **knowledge-bound** tasks but
NOT **harness-carried** routing (which is model-invariant with the catalog).

---

## TL;DR verdict

| Axis | Result |
|---|---|
| **Knowledge-bound task (litqa2 parametric MCQ)** | domainpro **+6.0pp** accuracy (0.2513 → 0.3116), coverage **+21pp** (0.553 → 0.764). Paired McNemar p=0.067 (24 fixed vs 12 broken) — **positive trend, same direction & magnitude as the +5.4pp knowledge slice.** Gain **DOES transfer** to the knowledge-bound harness metric. |
| **Routing-selection "control" (cross_domain_routing, catalog/described)** | domainpro **−16.0pp** (0.885 → 0.725). Paired McNemar **p=7.7e-6** — **domainpro significantly WORSE.** NOT model-invariant in this instrument; the adapter *regressed* LLM menu-selection. |
| **param_prefill (harness-assisted extraction)** | domainpro **−6.2pp** F1 (0.628 → 0.566); precision 0.82 → 0.67; must_not_fill violations 34 → 75. domainpro over-fills — **regressed.** |

**Bottom line:** The +5.4pp knowledge gain reflects in the end-to-end harness **only on the pure
parametric-knowledge task (litqa2, +6.0pp)**. On the two harness-assisted tasks it does **not lift and
actively regresses** them, because the CPT+SFT stack traded general **instruction-following / output
discipline** for domain knowledge: domainpro emits **238 output tokens on average vs base's 9** on
routing (26×; p95 latency 40 s), rambling instead of answering tersely, and over-fills parameters.

The hypothesis is **partially confirmed** (knowledge-bound ↑) and its "routing unchanged" prediction is
**refuted for the LLM-selection instrument** — with an important caveat below.

---

## Per-task table (real `score.py` numbers)

| Task | Instrument (what score.py reports) | base | domainpro | Δ (dp − base) | Paired significance |
|---|---|---|---|---|---|
| `cross_domain_routing` `--mode catalog --catalog-style described` | routing accuracy (acceptable_alts credited) | **0.885** (177/200), CI [0.833, 0.922] | **0.725** (145/200), CI [0.659, 0.782] | **−0.160** | McNemar χ²=20.0, **p=7.7e-6** (dp worse: 8 fixed / 40 broken) |
| `litqa2` (parametric MCQ, no retrieval) | accuracy = correct/all | **0.2513** (50/199), CI [0.196, 0.316] | **0.3116** (62/199), CI [0.251, 0.379] | **+0.0603** | McNemar χ²=3.36, **p=0.067** (dp better: 24 fixed / 12 broken) |
| `litqa2` | coverage = answered/all | 0.5528 | 0.7638 | +0.211 | — (dp abstains less) |
| `litqa2` | precision = correct/answered | 0.4545 | 0.4079 | −0.047 | — |
| `param_prefill` | param_F1 (key+value exact) | **0.6275** | **0.566** | **−0.0615** | precision 0.820 → 0.667; recall 0.508 → 0.492 |
| `param_prefill` | must_not_fill violations (lower better) | 34 | 75 | +41 (worse) | domainpro over-fills |

All three tasks run for **both arms** against the same served endpoint, identical prompts
(`run_baseline.py`/`score.py` unmodified), same items.

### Why routing & param_prefill regressed (root cause, not a parse artifact)

- Routing predictions: **0 empty, 0 truncated-garbage** for both arms — the parser works. The difference
  is behavioural. base mean output = **9 tokens** (clean terse name); domainpro mean = **238 tokens**
  (47,705 vs 1,828 total output tokens, 26×), p95 latency **40 s** vs 1.9 s. domainpro writes long
  "reasoning" and the first catalog name the parser finds is often a plausible-but-wrong neighbour
  (e.g. gold `nf-core/scrnaseq` → `nf-core/scnanoseq`/`nf-core/scdownstream`; gold
  `nf-core/differentialabundance` → `nf-core/gsea.`).
- param_prefill: domainpro's must_not_fill violations **doubled** (34→75) and precision fell 0.82→0.67 —
  same failure mode (fills things it shouldn't, ignores the "only if explicitly specified" instruction).

This is a genuine **instruction-following / format-discipline regression** introduced by the CPT+SFT
adapter stack, independent of any knowledge change.

---

## IMPORTANT caveat on the "harness-carried control"

The task framed `cross_domain_routing --catalog-style described` as the *harness-carried control* expected
to be model-invariant. **It is model-dependent, not model-invariant**: in this instrument the **LLM itself
picks** a name from a described menu, so its weights matter — and indeed they moved it (down 16pp).

The **true production harness-carried routing** is the **dense-cosine catalog resonance** of
`UnifiedWorkflowSearch` / the lane arbiter (catalog embeddings, 39%→97% dev) — that path **does not invoke
the served LLM weights at all** and is therefore the genuinely model-invariant component. **It was NOT
exercised by this test** (the harness's `--catalog-style described` menu-pick is an LLM-selection proxy,
not the retriever). So:

- **Confirmed:** the LLM's *own* menu-selection ability is model-dependent and the domain adapter degrades it.
- **Untested here:** whether the dense-retrieval harness-carried routing is model-invariant (it is by
  construction, but this run did not measure it). A follow-up should run routing through the real
  `UnifiedWorkflowSearch` retriever with base vs domainpro only as the downstream LLM, to isolate the
  retriever (expected ~0) from the LLM-selection head (shown here to regress).

---

## What this means for the program

1. **Knowledge gains transfer to knowledge-bound end-to-end metrics** (litqa2 +6.0pp, matching the +5.4pp
   slice) — the concept-CPT is doing real work on parametric recall.
2. **But the fuller-CPT domainpro is a net negative on the harness-assisted tasks** because it regresses
   instruction-following/terseness. Promoting it as the live-chat model as-is would **drop routing
   (−16pp) and param extraction (−6pp F1)** — the two most user-visible chat capabilities.
3. **Recommendation:** do NOT ship domainpro as the single live model on the strength of the knowledge
   slice alone. Either (a) add format/terseness discipline to the SFT mix (short-answer, "respond with
   only X" exemplars, anti-rambling) and re-run this harness, or (b) keep base for routing/extraction and
   use domainpro only where parametric knowledge is the bottleneck (findings narration, QA), with the
   dense retriever carrying routing. This matches the task-split thesis: **harness carries
   retrieval/rule/verifier; the LLM is bound on knowledge/findings** — domainpro helps the LLM-bound
   knowledge axis but hurts the format-bound axes.

---

## Reproduction / infra

- **Model reconstruction (no 18 GB transfer):** base = HF `Qwen/Qwen3.5-9B`
  @ `c202236235762e1c871ad0ccb60c8ee5ba337b9a`; domainpro = base **+ merge** midtrain adapter
  `eval_staging/cpt1200/` (`merge_and_unload`) **+ apply** SFT adapter `eval_staging/sft/` — the exact
  `spot_cpt800_worker.py --merge-adapter` pattern (same reconstruction that produced the +5.4pp slice in
  `spot_eval_full_entry.sh`).
- **Serving:** `evaluation/local_trial/harness_shim.py` — a tiny FastAPI OpenAI-compatible
  `/v1/chat/completions` over the local transformers model (one arm per process). BASE tokenizer + chat
  template for both arms, thinking disabled, greedy (temp 0) — apples-to-apples (only weights differ).
  9B bf16 (~18 GB) loads fine on the L4 one model at a time; vLLM not needed.
- **Harness:** `public_export/run_baseline.py` + `score.py` **unmodified**. Routing used
  `--catalog-style described` with the real **`backend/database/galaxy_ai_tools.db`** (324 MB, staged to
  S3 → box; 4,156 menu-eligible workflows; `description`/`annotation` columns present).
- **New files (additive):** `evaluation/local_trial/{harness_shim.py, spot_harness_entry.sh,
  spot_harness_bootstrap.sh}`; code tarball
  `s3://.../20260912/code/harness_eval_code.tgz`; payload+DB `s3://.../20260912/eval/harness_payload/`.
- **Spot box:** `g6.2xlarge` (1× L4 24 GB), **us-west-2c**, spot, instance `i-0ed41eb86442957d1`.
  Launched 04:12:22Z, self-terminated (`shutdown -h now`) after `Worker exit: 0` (~1.5 h end-to-end:
  bootstrap + base download + 2 arms × 3 tasks). **Capacity was tight** — `g6e.xlarge`/`g6.2xlarge` hit
  `InsufficientInstanceCapacity` across us-west-2a/b/d before 2c on g6.2xlarge succeeded (AZ/type cycling
  via `spot_launch.sh`). Spot price elevated by the crunch (~**$0.80/hr**) → **run cost ≈ $1.2**.
- **Env (bootstrap):** torch 2.14.1 / transformers 5.18.0 / peft 0.21.2 (pinned, matches training) +
  fastapi/uvicorn/openai.
- **Outputs (predictions + usage sidecars + scores + logs):**
  `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/eval/spot_harness_20261006_041559/`

## Honesty notes / unrun
- All numbers above are **real `score.py` output** on 200/199/170 items; no fabrication.
- The litqa2 +6.0pp is a **positive trend (p=0.067), not significant at 95%** — CIs overlap; the paired
  test is more powerful than the marginal CIs and points the right way, but it is suggestive, not proof.
  Routing −16pp is unambiguous (p=7.7e-6).
- **Not run:** the true dense-retrieval harness-carried routing (model-invariant by construction) — see
  caveat; `biomni_eval1` is not wired as a public_export RealBio task (the knowledge slice lives in
  `eval/med_today_20261003/openbook.jsonl`, measured separately by `spot_cpt800_worker.py`), so litqa2 was
  used as the in-harness knowledge probe. pbpk/boin/drug_discovery_e2e not run (out of scope for the
  knowledge-vs-routing contrast).
