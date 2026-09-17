# Proposal: a private, generalizable local LLM for BioMate (v1 — pre-code-review)

> Status: v1 documents the answer + proposal from the Paper2Agent/ScienceBuddy analysis. A v2
> "Adjustments" section will be appended after re-surveying BioMate's existing code/docs, so we build
> on what exists rather than duplicate it. See [[RECURSIVE_HARNESS_LEVERAGE]], [[TASK_CATALOG]],
> [[QWEN27B_REALBIO_BASELINE]], [[SELF_EVOLVING_SURVEY]].

## 1. Goal (realigned)
A **local** LLM for BioMate, required by **data sovereignty** (sensitive data cannot leave the
network). It must be **capable, flexible, and generalizable** across the ~28 catalogued task types,
ideally matching cloud/open LLMs — not a benchmark-point chaser.

## 2. What we established empirically
- Our on-prem **Qwen3.8-27B is on par with hosted Qwen3.8-Max** across 8 RealBio tasks.
- Fine-tuning gains are **format-specific** and single-task tuning causes **negative transfer**;
  **format-matched joint** training gives real but **modest, data-limited** gains.
- The durable routing lever is **retrieval** (hybrid recall@20=0.95), not weights.
- ScienceBuddy shows the **inner loop** (harness/skill/memory evolution, model frozen) delivers a
  **larger, cheaper, fully-local gain (+20pp)** than the weight fine-tuning we focused on.

## 3. Architecture (small local model + strong scaffolding)
Because a small local model is weaker than frontier cloud LLMs, we compensate with scaffolding —
validated by ScienceBuddy (harness) and Paper2Agent (tools):

1. **Local model tier:** Qwen3.8-27B (primary) + optional Qwen3.5-4B (fast paths); both run on-prem.
2. **Knowledge in retrieval/tools, not weights:**
   - Hybrid **retriever** over the 4,200-workflow / 12,312-tool DB (recall@20=0.95) for routing/lookup.
   - **MCP tools** via Paper2Agent's Paper2MCP: convert bio tools/workflows/papers into validated
     callable tools (593/599 pass rate); capability grows by adding tools, no retraining.
3. **Interaction + memory layer (compensates for the small model):**
   - **Confirmation loops:** when the model's confidence/verifier is low, ask the user to confirm
     (workflow choice, params, destructive actions) rather than guess.
   - **Adaptive memory:** persistent workspace (task, decisions, files, params, corrections);
     dialogue/feedback → tasks + rubrics (ScienceBuddy "Harbor tasks"), never treating user approval
     as ground truth.
4. **Recursive self-improvement (fully local):**
   - **Inner loop (do first):** a local 27B "proposer" diagnoses failures on RealBio + production logs
     and proposes **bounded edits** to instructions/skills/memory-config; accept only if grounded
     verifiers (execution/schema + RealBio rubrics) improve. No GPU-heavy training.
   - **Outer loop (later):** GRPO RL (SkyRL) on the task model under the improved harness, rubric
     rewards = executable/schema checks + judges. ReST-EM-style, real data mixed in (anti-collapse).

## 4. What to leverage vs build (open-source, MIT)
- **Leverage:** ScienceBuddy `simple_scibuddy` + SkyRL (harness + RL, our exact model family);
  Paper2Agent Paper2MCP + prebuilt scverse/AlphaGenome servers; our hybrid retriever; our grounded
  data-gen + independent auditor; our RealBio harness as the rubric/verifier layer.
- **Build:** the local edit-proposer wiring (swap ScienceBuddy's frontier proposer for our 27B); the
  BioMate-specific skill/instruction library; the confirmation + memory policies tied to verifier
  confidence; production-log → rubric ingestion.

## 5. Phased plan
- **P0 (now, no GPU):** stand up the inner-loop harness-evolution over RealBio + execution verifiers
  with the local 27B proposer; measure fixed-model lift (target: replicate ScienceBuddy's ~+20pp).
- **P1:** wire the retriever as the routing front-end + Paper2MCP tools; add confirmation/memory layer.
- **P2:** outer-loop GRPO RL (SkyRL) under the evolved harness; per-task RealBio + LifeSciBench eval.
- **P3:** production self-evolving loop (log → verify → evolve harness → periodic RL), collapse/leakage
  guards, open-baseline comparison (Aloe/OpenBioLLM/Meditron).

## 6. Open question for v2 (resolved by the code review)
How much of the interaction/memory/tool/retrieval layer **already exists in BioMate** (T03 clarify,
T04 session memory/compression, MCP tools, intent system, disambiguation)? The proposal must extend
those, not rebuild them — addressed in the appended v2 adjustments.

---

# v2 — Adjustments after re-surveying BioMate's code (what already exists)

**Headline:** BioMate already provides, at **production** maturity, most of the scaffolding the v1
proposal assumed we'd build. The local-LLM effort is therefore **much smaller and more feasible**
than framed — it's mostly (a) serve the local model in production, and (b) *close a feedback loop
that already captures the data*, on top of an existing skills/memory/retrieval/eval stack.

## What already exists (extend, don't build)
| Capability | BioMate today | Maturity | Key files |
|---|---|---|---|
| **Retrieval/RAG** | FTS + **BGE + MiniLM hybrid**, 2,455 wf indexed, source/exec-quality ranking | **PRODUCTION** | `unified_workflow_search.py`, `vector_search.py`, `query_analyzer.py` |
| **Skills** (ScienceBuddy inner-loop target) | 9 expert + **~1,818 Bioconductor** skills, trigger-detect + compose + system-prompt inject | **PRODUCTION** | `skill_manager.py`, `agents/skill_loader.py`, `skills/*.md` |
| **Memory** | episodic + procedural + `correction_log` tables, session load/enrich, context compression | **PRODUCTION** | `memory-repository.ts`, `memory-integration.ts`, `agentic_memory.py`, `context-compressor.ts` |
| **MCP tools** | 17 published tools, central manifest | **PRODUCTION (static)** | `tools_manifest.py`, `biomate_mcp_server.py` |
| **Offline eval harness** | 164 files, scorers, `results_store`, stability, multi-model (**Ollama**) adapters | **PRODUCTION** | `evaluation/core/*`, `ollama_eval_client.py` |
| **Provider abstraction** | OpenAI/Anthropic/Gemini/"local" + fallback chain | partial | `llm_client.py`, `local_inference.py` (stub), `frontend/server/local-llm.ts` |
| **Confirmation/clarify** | disambiguation cards, prerequisites validator, confidence fields | **STUB** | `workflow-prerequisites-validator.ts`, `galaxy-assistant.ts` |

**Implication:** my earlier "build a retriever" was re-deriving `unified_workflow_search.py` (already
hybrid FTS+BGE). And ScienceBuddy's inner-loop "evolve skills/instructions" maps **directly onto
BioMate's existing `skill_manager`** — we evolve the skills that already exist, not a new system.

## The genuine gaps (what to actually build)
1. **Local model in PRODUCTION (the data-sovereignty core).** Today production is cloud-only; local
   is eval-only (Ollama) + a `local_inference.py` stub. Build: serve Qwen3.8-27B on-prem
   (vLLM/Ollama), complete the `llm_client` local path + `local-llm.ts`, add hybrid routing
   (simple→4B/local, hard→27B), air-gapped deploy docs.
2. **Close the feedback loop (recursive self-improvement).** `correction_log` + `project_episodes`
   are *captured but never used*. Build the ScienceBuddy **inner loop on the existing stack**: local
   27B proposer diagnoses failures on the **offline eval harness + production correction_log/episodes**,
   proposes **bounded edits to existing skills/instructions** (`skill_manager`), accept only if the
   eval harness (our RealBio + execution/schema verifiers = rubrics) improves. No new skill system,
   no GPU for the inner loop.
3. **Finish confirmation/interaction (small-model compensation).** Complete blocked-required-param
   gating + verifier-confidence→ask-user + type/cost confirmation on top of the existing validator.
4. **Enhance memory (small additions).** cross-session synthesis of `correction_log`→preferences;
   **dense** episode retrieval (reuse `vector_search`); history-based rerank of retrieval candidates.
5. **Dynamic tools via Paper2MCP.** Add dynamic MCP registration + convert bio papers/tools to
   validated MCP tools (Paper2Agent) — makes capability grow without retraining.
6. **Outer-loop RL (last).** SkyRL/GRPO on the 27B under the evolved harness — only after 1–3 land.

## Revised phased plan
- **P0 — Local serving in production** (the actual requirement): vLLM/Ollama serve 27B, wire
  `llm_client` local path, hybrid routing, air-gapped deploy. *This is the point of the whole project.*
- **P1 — Close the inner loop on the existing stack:** local-27B proposer + `skill_manager` edits +
  offline-eval/execution rubrics + `correction_log`/episodes as tasks. Target: replicate
  ScienceBuddy's ~+20pp fixed-model lift, fully on-prem.
- **P2 — Finish confirmation + memory gaps** (blocked-param gating, dense episode retrieval,
  cross-session synthesis, history rerank).
- **P3 — Paper2MCP dynamic tools; then outer-loop GRPO RL; then open-baseline + LifeSciBench eval.**

## Net correction to strategy
The earlier weight-fine-tuning arc (LoRA on RealBio) was the **outer loop on a model that's already
competitive** — modest returns. The high-leverage, mostly-non-GPU work is: **(1) make the local
model the production path, and (2) turn on the inner loop over BioMate's already-built skills + memory
+ eval.** BioMate is ~70% of a ScienceBuddy-style system already; we mainly need to serve locally and
close the loop.
