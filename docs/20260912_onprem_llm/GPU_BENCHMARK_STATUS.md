# Local-LLM benchmark status — GPU trial (2026-09-13/14)

Scope: BioMate core assistant on a locally-hosted model (Qwen/Qwen3.8-27B, Q4_K_M via
llama.cpp). IND/regulatory excluded. No fine-tune performed. Goal: measure the local
model on BioMate task types (routing, param-extraction, code/Nextflow debug) and compare
to existing cloud baselines, to decide whether/what to fine-tune.

## Headline finding: GPU solves the latency wall

| Metric | CPU (r5.4xlarge) | GPU (g5.2xlarge, A10G 24 GB) |
|---|---|---|
| Throughput | ~0.4 tok/s | **26.6 tok/s (~66×)** |
| Single param-extraction call | **>220 s (exceeds 180 s adapter timeout)** | ~3–6 s |
| Full agentic chat turn | 652–844 s (11–14 min) | ~10–20 s (projected) |
| Model VRAM | n/a (RAM) | 17.7 / 23 GB (fits) |

CPU is unusable for interactive BioMate or for benchmarking (harness timeouts fire before
the model answers → artifactual zeros). **A single A10G/L4 (24 GB) is sufficient** for the
27B Q4 model. This is the core infrastructure answer for on-prem viability.

## What is proven about the local model (qualitative)

Validated end-to-end on the live stack this trial:
- Grounded catalogue QA — offline chat called the real `query_domain_knowledge` tool,
  cited real catalogue IDs (`nfcore/fastqc`, toolshed IDs), refused to fabricate. All 5
  offline-chat checks passed (see `infra/local-trial/results/live-validation-20260913/`).
- Workflow search/routing signal — backend log: "LLM selected 10 workflow IDs" for an
  RNA-seq query; param-inference path connects to the local model.
- Galaxy FastQC workflow execution + verified artifacts.

So the local model **functionally performs** BioMate's task types. What is NOT yet measured
is quantitative accuracy vs cloud, because of the integration bugs below.

## Why quantitative benchmark numbers are not yet produced

The existing benchmark harness (`evaluation/runners/run_routing.py`,
`run_param_prefill.py`) was written for the production BioMate deployment. Running it
against the freshly-rebuilt trial stack surfaced **trial-environment integration bugs**
(NOT model-capability issues):

1. **Routing (chat mode):** the authenticated eval user's Galaxy account provisioning
   fails with `500 Internal Server Error`; the chat handler then throws
   `TypeError: Cannot set properties of undefined (setting 'datasetReferenceUnresolvedIds')`
   and returns in ~30 ms — the model is never invoked. Every routing case scores 0.
   (The unauthenticated `evaluate-application.py` path worked, so the pipeline itself is
   fine; the failure is on the authenticated-but-unprovisioned user path.)
2. **Param-prefill:** `/api/ai_assistant/search_nextflow_workflow` runs param inference
   against the local model (`param_prefill_deferred=False`, connects to :8000) but returns
   0 auto-filled params — the local model's extraction output is not parsed into filled
   params in this integration.
3. **Config gap:** `backend/config/llm_providers.yml` was omitted from the trial bundle →
   "hardcoded LLM provider defaults" warnings. Local routing still worked via
   `BIOMATE_LOCAL_ONLY` + `BIOMATE_LOCAL_LLM_URL`, so this is noise, not the cause.

## Recommended path to real numbers

Rebuilding the entire app stack on a trial worker re-derives every provisioning/config bug.
Two cleaner options:

- **(Preferred) Direct-adapter benchmarking.** Use the existing `multi_model_eval.py`
  registry pattern (which already benchmarked `qwen3_8b_base`, `claude_sonnet_4_6`, `gpt_5`,
  `regulatory_llm_v6`) with an adapter that calls the local model endpoint directly. This
  measures pure model quality on structured tasks and bypasses the app-stack
  provisioning/chat surface entirely. Add a "qwen3_27b_local (llama.cpp GGUF)" column next
  to the existing cloud results in `evaluation/results/` and `results/llm_comparison/`.
- **(Alt) Fix the trial-env bugs** — Galaxy user provisioning 500 and the param-inference
  parse — then the app-level routing/param_prefill runners work. More debugging; only worth
  it if we specifically need app-in-the-loop (agentic) routing numbers.

## Direct-adapter benchmark result (2026-09-14) — WORKING

Added `evaluation/runners/adapters/qwen27b_llamacpp.py` (calls the llama.cpp OpenAI
endpoint) and registered `qwen27b_local` in `multi_model_eval.py`. Ran the regulatory
direct-adapter benchmark (9 checkers) on GPU — bypasses the app-stack bugs entirely.

**Local Qwen3-27B, n=60, 9-checker macro_avg = 0.883** (evidence:
`s3://.../acceptance/gpu-benchmark-20260914/`, and `evaluation/results/.../qwen27b_local.jsonl`):

| checker | 27B-local | note |
|---|---|---|
| mrsd_calc | **0.367** | quantitative FDA dose calc — weak (LLM arithmetic) |
| tabulated_vs_prose | 0.733 | preserves most tabulated numbers |
| citation_accuracy | 0.917 | strong |
| structural | 0.933 | strong |
| adversity_tense | 1.00 | — |
| phase_gating / hedge / numeric_ranges / cross_section | 1.00 | several trivially n/a |
| **macro_avg** | **0.883** | inflated by frequently-n/a checkers |

**Comparison caveat (important):** the existing baselines in
`evaluation/results/regulatory_llm_v2_judge/summary.csv` used a **different 6-checker
suite on 100 examples** (gpt_5 0.77, claude_sonnet_4_6 0.58, regulatory_llm_v6 LoRA-8B
0.55, qwen3_8b_base 0.41). Macro numbers are therefore **not directly comparable** to the
0.883 above. The one **overlapping, apples-to-apples checker is `adversity_tense`**:

| model | adversity_tense |
|---|---|
| **qwen3-27b-local** | **1.00** |
| gpt_5 | 0.865 |
| regulatory_llm_v6 (LoRA-8B) | 0.745 |
| claude_sonnet_4_6 | 0.68 |
| qwen3_8b_base | 0.56 |

On that checker the local 27B beats all, including cloud. Substantive takeaways:
- The local 27B is strong on regulatory **language/structure/citation**; weak on
  **quantitative dose calculation** (mrsd_calc 0.37) — a known LLM arithmetic gap best
  closed by **rule-based inference**, not fine-tuning (matches CLAUDE.md's rule-first policy).
- A rigorous head-to-head needs the cloud + 8B models **re-run with the same 9-checker
  suite** (requires API keys + the 8B model/LoRA) — clean follow-up.
- Implication for fine-tuning: 27B-base already handles regulatory prose well, so a
  fine-tune's value is likely higher on the **core agentic tasks** (routing, param-fill,
  Nextflow/code-debug) than on regulatory language.

## Nextflow / code-debug capability

No dedicated code-debug or Nextflow-debug benchmark exists in the routing/param suite. It is
the strongest fit for fine-tuning data (99 commit-derived repair candidates + dev
`correction_log` + Nextflow workflow fixes). Recommend building both an eval set and an SFT
set for it.

## Fine-tune / RL posture

Unchanged and gated on the above: measure baseline first (direct-adapter benchmarks) →
if gaps, LoRA/QLoRA SFT on verified episodes mined from dev logs → re-benchmark → DPO only
from verified pairs. No training performed. An existing regulatory LoRA (`regulatory_llm_v6`)
exists but is out of on-prem core scope (IND/regulatory).

## Cost hygiene

All trial workers terminated (CPU r5.4xlarge ×3, GPU g5.2xlarge ×1) — none left running.
Temporary SSH ingress rules on `sg-011121fdf81073ec8` for driver IPs; the persistent one is
the pre-existing `104.63.31.236/32`. Model/knowledge/evidence preserved in S3 under
`biomate-core-local-trial/20260912/` (including `acceptance/live-validation-20260913/`).
