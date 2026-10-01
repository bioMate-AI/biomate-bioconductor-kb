# BioMate × open-source AI-agent techniques — survey, gap analysis, plan (2026-10-01)

Grounded in a codebase inventory (file-level) of /Users/kky/biomate-review + /Users/kky/biomate-connector,
mapped against an open-source survey (Aviary, PaperQA2, DSPy, Biomni, distillation/critique work) and our own
on-prem-LLM evals. Purpose: stop reinventing what we have; add only the genuine gaps.

## Executive summary
BioMate already implements **9 of 13** capabilities in production (retrieval, graders, research agent,
provider routing, MCP+instruments, code exec, memory, chain planner, know-how context) and has an **advanced
training pipeline (RAG-SFT with hard-negatives + DPO + verifier-gated SFT)**. The genuine gaps are a short,
high-value list: **CoT-distillation, a unified verification layer + inference-time majority-vote, a trained
critic, a cite-or-abstain contract, DSPy prompt-opt, robustness-delta eval, RL-from-agent-interactions, and a
know-how retriever.** Most are *polish/extend*, not *build-from-scratch*.

## The matrix
| capability | BioMate HAVE (file) | best OSS ref | gap → ACTION |
|---|---|---|---|
| Dense/semantic retrieval | HAVE — `vector_search.py` VectorToolSearch (BGE), `unified_workflow_search.py` (FTS5+dense+Pass-0 LLM browse) | PaperQA2, RAG Foundry | none — strong; reuse for all tasks |
| Research + anti-confab | HAVE — `agents/research_agent.py`, `literature_clients.py`, conflict-marker, DB-lookup-before-synthesis | **PaperQA2** cite-or-abstain | **PARTIAL in practice** (research_query still confabulates when recall=0) → **add cite-or-ABSTAIN contract** |
| Deterministic graders | HAVE — `llm_judge.py`, `evaluation/scorers/*`, consensus | VeriLA | judge is LLM-based (we proved unreliable) → use F1/accept-set + trained critic |
| Critic / self-verification | HAVE but **prompt-based** — Haiku judge, `committee.py` | **adversarial critique distillation** | → **train a critic model** (fix self-verification bias) |
| QC / verification loop | **PARTIAL** — domain auto-loops (`autoloop_benchmark_adapter.py`), not unified | **Aviary** env-rewards | → **unify as a VerificationLayer** + **inference-time majority-vote / pass@k** (free accuracy) |
| RAG-SFT training | HAVE — `build_rag_routing_sft.py` (retrieved candidates + hard-negatives) | RAG Foundry | extend from routing → **generative tasks (findings/decomp)** |
| DPO / verifier-gated SFT | HAVE — `build_dpo_pairs.py` (synthetic+rejection), verifier-gated SFT | — | keep; (DPO fairly tested = neutral for routing) |
| CoT-distillation | **MISSING** | distillation-without-knowledge; Insilico stage-3 | → **add frontier-CoT-trace distillation stage** (our #1) |
| RL-from-agent-interactions | **MISSING** | **Biomni-R0** (32B Qwen, RL from agent runs) | → consider later (bigger); our QC loop = reward source |
| Chain / decomposition planner | HAVE (prototype) — `chain_planner.py` (~50% port coverage), curated chains, TaskDecomposer | — | polish port coverage |
| Memory | HAVE (beta) — `memory/*` (User/Episodic/Procedural), LTM→Postgres, recall | — | benchmark recall in prod |
| Code execution | HAVE — `compute/sandbox/*` (trust levels, tiers) | Aviary notebook env | none |
| Multi-LLM routing | HAVE — `llm_router.py` (Anthropic/Gemini/Zhipu + local fallback, cost-aware) | — | none |
| MCP + instruments | HAVE — 24 MCP tools (`tools_manifest.py`), **18 instrument connectors** (opentrons/nanopore/LCMS/qPCR/cryo-EM/DBTL…) | Biomni MCP | none — a real moat |
| Prompt management | **PARTIAL** — hand-written templates, no optimization | **DSPy** | → pilot DSPy on routing/param |
| Know-how library | HAVE (embedded) — `scientific_context`, `benchmark_knowledge.py`, `domain_registry.py`, 2.5k keyword weights | Biomni Know-How Library | → **dedicated GTN/protocol retriever** (not just embedded) |
| Robustness eval | **MISSING as an axis** | LongevityBench rephrase-shift | → add **paraphrase + candidate-shuffle delta** |

## The genuine gaps to ADD (prioritized)
1. **CoT-distillation stage** (MISSING) — frontier chain-of-thought traces → SFT on the 5 hard generative tasks
   (findings/decomp/out-of-catalog/param-reasoning). Highest value; our F1 eval shows these are real-but-modest.
2. **Extend RAG-SFT to generative tasks** (HAVE for routing) — train with retrieved facts in-prompt so the
   model grounds on provided knowledge (reuse `build_rag_routing_sft.py` machinery).
3. **Unified VerificationLayer + inference-time majority-vote / pass@k** (PARTIAL/MISSING) — consolidate the
   scattered auto-loops; add cheap sampled-consensus at inference (Aviary-proven free accuracy).
4. **Trained critic** (prompt-based today) — adversarial-critique distillation; fixes the LLM-judge
   unreliability we measured (content_overlap/clustermix=1.0 failures).
5. **Cite-or-abstain contract** for research_agent (confab persists) — PaperQA2-style: answer only from
   retrieved passages with citations, else abstain.
6. **Robustness-delta eval** (MISSING axis) — report each task under paraphrase + candidate-order shuffle.
7. **DSPy prompt-opt pilot** (manual today) — compile routing/param prompts.
8. **Know-how retriever** (embedded→dedicated) — GTN tutorials/protocols as a contextual retrieval layer.
9. **RL-from-agent-interactions** (MISSING, later) — Biomni-R0-style; our QC loop already supplies rewards.

## Don't reinvent (already strong — reuse)
Retrieval (vector+FTS+LLM-browse), the 24-tool MCP + 18 instrument connectors (DBTL/closed-loop bridges),
multi-LLM routing, code sandbox, memory schema, DPO + RAG-SFT training pipeline, deterministic scorers,
scientific-context/know-how embedding. These ARE the harness moat — invest in the 9 gaps, not these.

## Execution plan (sequenced)
Phase A (cheap, high-value, all reuse existing infra):
- A1 CoT-distillation stage → re-eval F1 vs sft_v5.
- A2 extend RAG-SFT to findings/decomp.
- A3 robustness-delta eval + inference-time majority-vote (free accuracy).
Phase B (verification moat):
- B1 unify VerificationLayer (fold the domain auto-loops into one QC+remediation framework).
- B2 trained critic (adversarial critique distillation) to replace the Haiku LLM-judge.
- B3 cite-or-abstain for research_agent.
Phase C (platform):
- C1 DSPy pilot; C2 know-how retriever; C3 (optional) RL-from-interactions (Biomni-R0 analog).
Cross-cutting: BioMate-Bench publish requires grounded-gold rebuild + committee audit (prereq, documented).

## Honesty notes
- The inventory says "all 13 present," but CoT-distillation and RL-from-interactions are effectively MISSING,
  and research-anti-confab / QC-unification / trained-critic are PARTIAL in practice — don't over-claim "done."
- Our strongest card is the harness (retrieval+tools+instruments+verification), not model size — matching both
  Insilico (Claw) and Aviary (open agents beat frontier at ~100× less cost via env+verification).
