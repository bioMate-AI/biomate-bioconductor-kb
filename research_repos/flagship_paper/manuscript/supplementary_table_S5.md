# Supplementary Table S5 | Model-invariance analysis: BioMate performance as a function of the backend language model

**Purpose.** BioMate's headline claims rest on the assertion that "the intelligence is in the catalog, not the model." This table separates BioMate's benchmark results by whether a language model is exercised on the scored decision, and reports the dependence of each class on the configured backend model. Methods for the two run classes are in §Methods; every value traces to a committed file named below.

## S5.1 Two classes of result

BioMate exposes a deterministic retrieval-and-scoring path and a generation path. Which path serves a task determines whether the score depends on the backend model.

| Task (dimension) | Path serving the decision | Backend model exercised | Model-dependence |
|---|---|---|---|
| Cross-domain routing (D1) | Deterministic retrieval + scoring | **None** | **Invariant** |
| Parameter prefill (D1) | Rule + retrieval extraction | None (rule-first; LLM only as fallback for free-text values) | Invariant on the rule-covered majority; fallback-sensitive on free-text |
| Protocol-threshold QC (D1) | Deterministic gate evaluation | None | **Invariant** |
| Pharmacology — PBPK/BOIN (D2) | Deterministic numerical runner | None | **Invariant** |
| BiomniEval1 (D3) | Generation + LLM-judge audit | Claude Sonnet 4.6 (gen) + Claude Haiku (judge) | **Model-dependent** |
| BixBench / Verified-50 (D3) | Analysis-handler generation | Claude Sonnet 4.6 | **Model-dependent** |
| SGI-Bench (D3) | Generation + LLM-judge | Claude Sonnet 4.6 (gen) + Claude Haiku (judge) | **Model-dependent** |

## S5.2 Invariance of the engine-free results (evidence)

For the deterministic-path tasks, the backend model is *configured but not exercised* on the scored decision. Direct evidence is the reproducibility run, executed under the Sonnet-4.6 configuration (`model = biomate_claude_sonnet_4_6`): on the routing path it recorded **`mean_latency_sec = 0.0`** and **`total_cost_usd = 0.0`** across 24 workflows × 3 repeats (`evaluation/results/stability/routing_stability.json`), i.e. no model call was made on the routing decision (this file measured run-to-run agreement and carries `mean_score = 0.0`; the routing accuracy 0.965 comes from the separate committed RealBio scoring file, not this stability run). A path that issues no model call cannot vary with the model; therefore the routing score (0.965 [0.930, 0.983], RealBio; `results/biomate_dev/cross_domain_routing_c2ir.jsonl`) is invariant to the configured backend, and the same argument holds for protocol-QC and the deterministic pharmacology runner (zero LLM in the evaluation loop, §Methods).

**Reading.** The paper's load-bearing figures — routing, protocol-QC, pharmacology — are model-invariant *by construction*, not by empirical stability. This is a stronger property than run-to-run agreement: it removes the backend model as a source of variance entirely, and it is what makes BioMate deployable on any provider (including a user's own DeepSeek/Qwen/GLM account) without changing these results. It also bounds the answer to "which model powers BioMate": **none**, for the figures that carry the central claims.

## S5.3 Model-dependence of the knowledge results (measured)

The generation-path tasks (D3) do exercise a model and are expected to move with it. The reported values were produced with **Claude Sonnet 4.6** (generation) and a **Claude Haiku** judge (2026-04-29 run): BiomniEval1 macro-average 71.1%, BixBench/Verified-50 92.0% (46/50), SGI-Bench ≈40%. These are *not* invariant, and a stronger or weaker generator would shift them; the cross-model sweep quantifying this dependence is reported in S5.4.

## S5.4 Cross-model comparison of a generation-path task — accuracy **and** latency

Model selection for the generation path was made on committed cross-model runs, not by default. The broadest is `multitask_crossjudge_v1` (an earlier model snapshot — model names below, e.g. GPT-5 / Sonnet 4.6, differ from RealBio's GPT-5.6 / Gemini 3.1 Pro; n = 70; six regulatory-writing subtasks; cross-judged median-macro), reported here with per-response latency (`elapsed_s`) measured on **direct provider APIs** — the production serving path (`llm_client.py` defaults to `api.anthropic.com` / `api.openai.com` / `generativelanguage.googleapis.com`; OpenRouter is used only for user-supplied keys).

| Model | Median-macro [95% CI] | Latency median | Latency max | Selection read |
|---|---|---|---|---|
| GPT-5 | 0.532 [0.486, 0.576] | 8.0 s | 23.4 s | highest accuracy; loose tail |
| Gemini 3.1 Pro | 0.505 [0.458, 0.551] | 18.8 s | 34.6 s | accurate but **latency-disqualified** |
| **Claude Sonnet 4.6** *(selected)* | 0.443 [0.405, 0.483] | 10.1 s | **12.2 s** | **tightest tail — bounded worst-case** |
| GPT-5-mini | 0.435 [0.392, 0.479] | 7.7 s | 38.9 s | fast median, **39 s tail** |
| Claude Haiku 4.5 | 0.363 [0.323, 0.410] | 4.1 s | 6.5 s | fastest; lowest accuracy |

A separate open-model run (`model_selection`) records `gemma4:31b` at **160.5 s/task** — flatly disqualified on latency irrespective of score.

**Reading — selection is latency-gated, not accuracy-maximising.** GPT-5 leads on accuracy and median latency, but its worst-case (23.4 s), and the tails of GPT-5-mini (38.9 s) and Gemini 3.1 Pro (34.6 s), exceed the bound acceptable for an interactive, streamed response. Sonnet 4.6 carries the **tightest worst-case latency (12.2 s)** in the pool, at a median-macro not separable from GPT-5-mini and within a fixed accuracy band of the leaders. Sonnet 4.6 is the **deployed** choice, reflecting a preference for bounded worst-case latency under a minimum-accuracy floor. We are candid that on this evidence GPT-5 is the stronger option on **both** accuracy and median latency (only the max-tail favours Sonnet), so the choice is defensible on predictable-response-time grounds but **worth revisiting** — see the fragmentation audit's re-select-default note. Because these latencies were measured on direct provider APIs (the production path), the criterion applies as deployed; a routed (OpenRouter) path would require re-measurement.

**Consequence for the reported knowledge scores.** The D3 figures (BiomniEval1 71.1%, BixBench 92.0%, SGI-Bench ≈40%) were produced with this latency-selected mid-tier generator; they are therefore a **floor**, with headroom under a more accurate generator (GPT-5, +≈0.09 median-macro on the regulatory task) at the cost of a looser latency tail. The engine-free results (S5.2) are unaffected.

**Honesty note.** The cross-model evidence in this subsection is on the regulatory-generation task family (`multitask_crossjudge`/`model_selection`), not on BiomniEval1 itself; the selection *criterion* (bounded-tail latency + accuracy floor) is what generalises. A first BiomniEval1-specific arm through the full BioMate pipeline is now committed and reported in S5.5; a full macro-average cross-model sweep remains the next step.

## S5.5 First BiomniEval1-specific BioMate-through-a-model arm (committed run)

Enabled by the `resolve_model(role)` refactor (backend model set by `BIOMATE_MODEL`; verified end-to-end), we ran the first BiomniEval1 arm end-to-end through the deployed BioMate pipeline (runner `evaluation/runners/run_biomate_llm_matrix.py`; results `evaluation/results/biomni_eval1_devarm/eval_results.db` and `results/biomate_llm_matrix/biomni_eval1.csv`, dev, 2026-08-26):

| System | BiomniEval1 task | Backend model (observed) | n | Accuracy [Wilson 95%] | Latency median / max | LLM cost/item |
|---|---|---|---|---|---|---|
| BioMate (full pipeline, dev) | gwas_variant_prioritization | `gpt-5.6-luna` | 8 | **0.875** [0.529, 0.978] | 189.7 s / 325.5 s | ≈$0.0021 |

This is **one arm, not the sweep** — read with these caveats:

- **Single task type, small n.** All 8 items are `gwas_variant_prioritization` (the `--max-tasks 8` slice of the ordered task list). This is *not* the BiomniEval1 macro-average and is not comparable to the 71.1% macro figure (S5.3); it says only that on this one knowledge subtask BioMate answered 7/8 correctly through a mid-tier deployed generator, consistent with S5.4's "mid-tier generator is a floor" reading.
- **Single model.** This measures BioMate through the *current dev backend*, not a model sweep. The cross-model comparison across configured `BIOMATE_MODEL` values is the runnable, un-run procedure documented in `docs/20260826_BIOMATE_LLM_MATRIX_STATUS.md`.
- **The observed deployed backend is `gpt-5.6-luna`, not Sonnet 4.6.** Every one of the 8 responses carried `model = gpt-5.6-luna`. The dev chat path therefore currently serves GPT-5.6-luna, whereas the historical D3 scores (S5.3/S5.4) were produced under Sonnet 4.6 (2026-04-29). This is a deployment-config divergence noted for accuracy — it does not re-score the historical numbers, but it does mean the "Sonnet 4.6 is the deployed choice" statement in S5.4 describes the selection *decision*, not the model live on dev at this snapshot.
- **Latency is full-pipeline wall-clock** (retrieve → interpret → generate → score), not a bare provider-API `elapsed_s`; it is **not** comparable to S5.4's direct-API latency table.
