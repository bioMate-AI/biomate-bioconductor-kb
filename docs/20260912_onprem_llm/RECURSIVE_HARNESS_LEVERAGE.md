# Leveraging Paper2Agent + ScienceBuddy for a private, generalizable BioMate local LLM

Goal (realigned): a **local** LLM for BioMate — driven by **data sovereignty** (sensitive data cannot
leave the network) — that is capable, flexible, and generalizable across the ~28 catalogued tasks,
ideally matching cloud/open LLMs. Two recent open-source works are almost drop-in references.

## 1. ScienceBuddy — recursive-in-recursive self-improvement (the harness the user asked about)
arXiv 2609.17523 · repo `Gen-Verse/ScienceBuddy-RSI` (MIT) · site science-buddy.io

**Why it matters to us: it is nearly our exact setup.**
- Task model **Qwen3.5-4B**, helper **Qwen3.8-27B** — the *same models we have*. Proves a small local
  pair is viable.
- Task families **LitQA2 (literature), DbQA (database queries), ProtocolQA (protocol troubleshooting),
  GWAS** (895 tasks) — overlap our RealBio (protocol_QC≈ProtocolQA, DB/knowledge, GWAS).
- **224 tools across 22 modules** (genomics, molecular biology, databases, literature) — a tool layer
  like our 300M DB / MCP tools.

**The two recursions:**
- **INNER = harness evolution (model FROZEN):** an auxiliary model diagnoses failures from trajectories
  + rubric feedback and proposes **bounded edits** to (a) instructions/system prompts, (b) reusable
  **skills** (procedural steps, e.g. "gene-set membership check, cytoband lookup, DB evidence
  extraction"), (c) **context/memory settings**. Accept an edit only if it improves paired dev tasks.
  → **+20pp with NO model training** (31.1%→51.1% val). This is the "better scaffolding compensates
  for a small model" lever.
- **OUTER = model RL (GRPO):** train the task model under the *improved* harness with **rubric rewards
  = executable checks + fixed judges**, on fresh on-policy rollouts. → +19.5pp coverage (48.3%→67.8%).
- **Two-cycle co-evolution: 42.2% → 73.3% overall.**

**Dialogue → tasks/rubrics (the interaction+memory layer):** researcher requests/clarifications/
execution records/artifacts become "Harbor tasks" = instruction + assets + execution env + **rubric**
(scope, method requirements, evidence, expected artifacts). Crucially it does **NOT treat researcher
approval as ground truth** — grounded verification, the anti-collapse safeguard.

**Open-sourced (MIT):** `simple_scibuddy` (simplified agent), the harness + execution broker, **SkyRL**
integration for the RL stage, and docs (`docs/algorithm.md`, `docs/experiments.md`) with a frozen
715/90/90 split. Full product frontend is proprietary. Caveat: the edit-proposer is GPT-6 Astra
(frontier) but "pluggable" — for a fully-local BioMate we'd use our 27B helper as the proposer.

## 2. Paper2Agent — papers/tools → MCP agents (the generalizability mechanism)
arXiv 2509.06917 (Stanford, Nature) · repo `jmiao24/Paper2Agent` (MIT) · prebuilt HF Spaces

- **Paper2MCP**: paper + its codebase → an **MCP server** of validated tools (extract methods/params →
  tool schemas → wrapper code → automated functional/param/output/integration tests). **74/100 comp-bio
  papers agentified, 593/599 tools passed, 91.2%** on 300 questions.
- **Model-agnostic agent layer** (reason→act→observe, tool selection + chaining); supports local/open
  models. Prebuilt agents: **AlphaGenome, Scanpy, Tissue** (scverse — relevant to BioMate).
- Turns "papers/tools into executable APIs" → capability grows by **adding MCP tools, not retraining**
  → generalizable, and keeps **knowledge in tools/retrieval** (fits our "skill in weights, knowledge in
  retrieval" thesis and the 300M tool/workflow DB).

## 3. What we leverage (concrete)
1. **Adopt ScienceBuddy's `simple_scibuddy` + SkyRL** as the harness/RL starting point — it targets our
   exact model family and task types; MIT.
2. **Prioritize the INNER loop first (cheap, no big GPU):** auto-evolve instructions/skills/memory-config
   against our **RealBio harness + execution/schema verifiers** (our verifiers = their rubrics). This is
   likely a *bigger, cheaper* lever than the LoRA fine-tuning we did (they got +20pp fixed-model). Use our
   **local 27B as the edit-proposer** to stay fully on-prem.
3. **Add Paper2Agent's Paper2MCP** to convert BioMate tools/workflows/papers into MCP tools the local
   LLM calls → generalizability without retraining; start with the scverse/AlphaGenome prebuilt servers.
4. **Interaction + memory adaptation (user's instinct, validated):** implement the dialogue→rubric +
   persistent workspace + **confirmation loops**, with grounded verification (never user-approval-as-truth).
   For a small local model, this scaffolding is a first-class capability lever, not an afterthought.
5. **Keep our complementary assets:** grounded data-gen + independent auditor, the RealBio 27B baseline,
   the format-matched-joint-training lesson, and the hybrid retriever (recall@20=0.95).

## 4. Strategic correction this implies
Our fine-tuning work was the **OUTER** loop only. We under-invested in the **INNER** loop (harness/skill/
memory evolution + user interaction) — which ScienceBuddy shows is a large, cheap, fully-local gain and
which matches the user's interaction+memory intuition. **Next priority = build the inner-loop harness-
evolution + interaction/memory layer** (local 27B proposer, RealBio+execution rubrics), then outer RL.
