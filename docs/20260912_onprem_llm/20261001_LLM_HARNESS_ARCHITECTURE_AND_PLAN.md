# BioMate LLM × Harness — architecture, division of labor, and plan (2026-10-01)

Synthesis of our on-prem-LLM evals + the Insilico LongevityBench/Longevity-LLMs/Claw read + an open-source
survey of research-assistant / AI-scientist projects. This is the decision record + execution plan.

## 1. Core principle
**The LLM is a REASONER over RETRIEVED knowledge, not a knowledge store.** It proposes; the harness grounds,
executes, and verifies. Put *judgment under ambiguity* in the model; put everything *volatile, verifiable,
numeric, or stateful* in the harness.

## 2. Division of labor
| ON THE LLM (weights) | ON THE HARNESS |
|---|---|
| reasoning SKILL (interpret findings, decompose, compose, synthesize) | retrieval of all volatile facts (catalog, schema, KG, literature, data) |
| candidate/plan GENERATION | tool execution (ADMET/clocks/workflows — numeric prediction) |
| SELECTION among retrieved candidates (routing/lane/model-sel) | VALIDATION of every LLM output vs schema/catalog (drop/repair) |
| ambiguity resolution / clarify-or-proceed | VERIFICATION: deterministic graders + QC gate + multi-run consensus (LLM NEVER self-grades) |
| free-text → value mapping (the ambiguous slots) | deterministic rules: units, booleans, enums, aliases (the 80%) |
| | state, memory, provenance, defaults, orchestration control-flow |

Evidence: routing→base+retrieval (0.94, 4× confirmed); SFT wins reasoning tasks under F1 (0.43 vs 0.27);
mid-train/DPO fair negatives (don't put volatile knowledge in weights); LLM-judge/content_overlap failures
(don't let the LLM grade itself); knowledge_recall only 0.66 (LLM is an unreliable knowledge store).

## 3. Skill ≠ knowledge — and how to "build knowledge in"
The knowledge-intensive LLM tasks split into **skill (stable, finite → weights)** and **knowledge content
(vast, volatile → retrieved)**. You do NOT parametrize biology into a 4–9B (unreliable, stale, confabulates).
Three-layer recipe for the LLM's share:
1. **SFT the reasoning skill** (sft_v5 — done; wins 14/17 under F1).
2. **CoT-distillation** — frontier chain-of-thought traces teach step-by-step reasoning (the stage we skipped;
   Insilico's stage 3). Teacher→student structured-decomposition distillation, factual responsibility shifted
   to retrieval (reduces hallucination — see open-source §7).
3. **Scoped CPT on bounded, always-needed, STABLE priors only** (hallmark/pathway relations, analysis-plan
   shape, ADMET rules) — exactly Insilico's clock-formulas-in-weights. NOT the catalog/long-tail (mid-train neg).
Plus the enabling technique: **retrieval-augmented SFT** — train with retrieved knowledge IN the prompt so the
model learns to *ground on provided facts*, not recall them; knowledge stays in the swappable corpus.

## 4. Collaboration protocol (the loop)
```
harness PREPARE (retrieve candidates/schema/data) → LLM PROPOSE (select/generate/reason)
 → harness VALIDATE (vs schema/catalog; rules; fill defaults) → harness EXECUTE (tools/workflow)
 → harness VERIFY (graders/QC gate/consensus) → loop (feed failures back to LLM)
```
Worked — **param generation (100s of params)**: harness retrieves schema(allowed-values,defaults)+data
metadata; LLM sets only the ~5–15 context-dependent slots (genome/strandedness/single-end/thresholds); harness
fills defaults, applies rules, validates vs allowed-values, executes on Batch + programmatic check. The LLM
works a small bounded decision surface; it never emits the raw 100s. (This is RAG+judgment, NOT generation.)
Worked — **findings interpretation**: facts(gene/pathway) retrieved; result values from the run; LLM supplies
the reasoning; harness checks faithfulness. LLM = reasoning; harness = facts + verification.

## 5. Translation from Insilico (Cell 2026) → BioMate actions
- mid-train helps iff the task consumes parametric knowledge → **CPT only for quantitative tasks (ADMET/PBPK/
  BOIN)**, never routing. (Reconciles our mid-train negative.)
- **Add CoT-distillation stage** (their stage 3) on our hard generative tasks.
- **Anti-memorization eval**: paraphrase-shift + feature/candidate-order perturbation → add a robustness-delta axis.
- **Agent = small LLM + tools + N-D scoring + consensus + enrichment validation** → our target-nomination /
  closed-loop workflow (Claw's 14-hallmark × 30 → dedup → 328, 6-D score, 5-run consensus, 5.6× enrichment).
- **Model family by lane** (0.6B won a task, 9B overall) → Instant=tiny, Cloud=9B.

## 6. BioMate-Bench (publish a benchmark with the LLM — SEPARATE, complementary)
- NOT a LongevityBench clone (theirs = bio-data prediction; ours = **agentic orchestration**: route→param→
  compose→interpret). Real-bio-grounded via real workflows/tools/**accessions**/outputs.
- Tiers: L1 offline (grounded gold), **L2 real-execution** (config runs on Batch + programmatic output check —
  the unfakeable, harder-than-classification tier). Score LLM-attributable (context-dependent decisions)
  SEPARATELY from end-to-end (runs+passes) — don't credit the LLM for harness defaults.
- PREREQUISITE (non-negotiable): **grounded-by-construction gold + committee audit** (our generated gold was
  20–38% hallucinated; committee caught 80% in recipe data) + de-biased graders (F1/accept-set/L2).
- Open: task defs, cleaned gold, stub catalog, sft_v5. Keep: enriched DB, retriever, prod harness.

## 7. Open-source leverage — adopt, don't reinvent
| project | what to leverage | our status |
|---|---|---|
| **Aviary** (FutureHouse) — language-agent gym (POMDP), open non-frontier agents match frontier at ~100× lower cost; inference-time **pass@k oracle + majority-vote** | adopt the environment-training abstraction + **cheap inference-time verification (majority vote / pass@k)**; our QC loop ≈ their env rewards | our QC loop is this; formalize + add majority-vote |
| **PaperQA2** (FutureHouse) — citation-grounded multi-doc RAG, expert-level, anti-confabulation | adopt for research_query / findings (constrain to retrieved source + cite) — directly fixes our confabulation | we have retrieval; adopt the cite-or-abstain contract |
| **DSPy** — prompts as compiled/optimized programs | auto-optimize our per-task prompts/pipelines instead of hand-tuning | hand-tuned today → pilot DSPy on routing/param |
| **reasoning/structured-decomposition distillation** (teacher→student planner) | our CoT-distillation stage; shift facts to retrieval | planned (§3.2) |
| **adversarial critique distillation** (self-verification-bias fix) | train the QC-loop CRITIC adversarially (avoid LLM self-grading bias — our broken-judge lesson) | our committee/graders; make the critic a trained model |
| **RAG Foundry / Agent-UniRAG** — frameworks for retrieval-augmented LLM training | the mechanics of retrieval-augmented SFT (§3) | adopt the training recipe |
| **Biomni** (Stanford) — biomedical tool-env + tasks | tool environment + task set (already a benchmark we track) | keep; align BioMate-Bench |
| **GPT Researcher / STORM** — outline-driven cited synthesis, hybrid retrieval | report/findings generation pattern (outline→section→cite) | adopt for export_report/findings |
| **VeriLA** — interpretable agent-failure verification | our VerificationLayer design | adopt framing |

Do NOT reinvent: our UnifiedToolSearch/retriever, MCP tools (19) + lab connectors (10), QC loop — already built.

## 8. Prioritized experiments
1. **CoT-distillation stage** on the 5 hard generative tasks → re-eval F1 vs sft_v5. (cheapest, highest-value)
2. **Retrieval-augmented SFT** for findings/decomp (train with retrieved facts in-prompt).
3. **Clean CPT test on ADMET** (CPT priors → SFT → CoT) — decisive proof of the mid-train rule.
4. **Robustness-delta eval** (paraphrase + candidate-shuffle).
5. **Inference-time majority-vote / pass@k** (Aviary) — free accuracy on hard tasks.
6. **BioMate-Bench**: grounded-gold rebuild + committee audit → publish.
7. **Target-nomination workflow** (Claw-pattern) for drug-discovery closed loop.

## 9. Honesty notes
- Our current eval gold is contaminated (20–38% hallucinated routing; 80% in recipe) — do NOT publish or train
  on it before the grounded rebuild + committee audit.
- LLM-regression over raw features: route to TOOLS, don't make the LLM do it (keep numeric in the harness).
- Verification must be deterministic/trained-critic, never the task-LLM self-judging.
