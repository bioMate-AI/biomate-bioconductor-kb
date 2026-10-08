# Agent Patterns — Research Notes & BioMate Integration Plan

**Date:** 2026-10-08
**Scope:** Detailed notes on three external works + a grounded map of BioMate's own
orchestration, answering: *how do we make BioMate more flexible and smarter?*
**Lens throughout:** what we have · what we lack · what we can directly integrate.

---

## 0. Thesis (the one-paragraph answer)

Parallel multi-agent search — the pattern behind the "virtual pharma" system (Robin) —
is **one** agent pattern, not *the* pattern. The Nature Machine Intelligence result shows
multi-agent collaboration only helps when a single strong model's **baseline on that task is
below a capability-saturation threshold**; above it, extra agents add cost and *amplify*
errors. Claude Code's dynamic-workflow guidance gives the complementary engineering view: a
small inventory of orchestration shapes (single agent, pipeline, parallel fan-out, adversarial
verify, coordinator+roster) and an explicit rule to **match the shape to the task and not
over-spawn**. BioMate already owns the expensive substrate — durable cross-worker parallel
*run* tracking and a fully-built-but-**dormant** parallel-specialist orchestrator — but it has
**no runtime logic that chooses an agent pattern**, its findings step is a deterministic
single pass, and it has no aggregated live multi-run view. The upgrade that makes BioMate
"flexible and smarter" is therefore **not more agents** — it is a **capability-gated pattern
router** that picks single-vs-multi (and which multi) per scenario, plus a few targeted
imports (grounded literature RAG; an LLM-judge tournament for hypothesis triage; an
ensemble-consensus findings layer), all surfaced through a live task dashboard built over
run-state machinery that already exists.

---

## 1. WORK 1 — "Virtual pharma": FutureHouse **Robin**

### 1.1 Identity (with an important caveat)
- **Title:** *Robin: A multi-agent system for automating scientific discovery* (FutureHouse).
- **Primary artifact:** arXiv **2505.13400** (19 May 2025) — https://arxiv.org/abs/2505.13400 .
  Repo **https://github.com/Future-House/robin**, **Apache-2.0**.
- **Venue caveat:** reported by secondary sources as later in *Nature* (2026); **not confirmed
  as *Science***. The brief said "Science" — on current evidence no open-source virtual-pharma
  system is in *Science*; the mechanism match (parallel multi-agent finding-detection +
  open source) points unambiguously to Robin. **Flag for the user:** confirm whether a strict
  *Science* paper is meant, else proceed with Robin.
- **Underlying open substrate (the directly-reusable parts):** **PaperQA2** (*Language agents
  achieve superhuman synthesis of scientific knowledge*, arXiv 2409.13740,
  https://github.com/Future-House/paper-qa, Apache-2.0) and **Aviary** (arXiv 2412.21154,
  Apache-2.0).

### 1.2 What it does
End-to-end semi-autonomous discovery (human runs only the wet-lab): disease → literature review
→ ~10 mechanism hypotheses → LLM-judge tournament → top assay → ~30 candidate molecules →
deep per-candidate literature review → tournament → human experiment → **autonomous data
analysis** → consensus finding → refined hypotheses → repeat. Case study (dry AMD) surfaced
**ripasudil** (a ROCK inhibitor) and an ABCA1 lipid-efflux mechanism from RNA-seq.

### 1.3 Agent architecture — the "parallel" pattern, precisely
Three agents orchestrated by a **scripted hierarchical workflow** (not free-form debate):
- **Crow / Falcon** — concise / deep literature synthesis, built on **PaperQA2** (parallel
  evidence gathering: search → per-chunk rerank+contextual-summary → citation-graph traversal).
- **Finch** — data-analysis agent that **launches 10 independent analysis trajectories over the
  same dataset, then a meta-analysis step reconciles them into one consensus finding.** This is
  the literal "multiple agents searching data in parallel to detect findings."
- **Aggregation = LLM-judge tournament** (pairwise/round-robin, up to ~300 comparisons), not a
  single ranking pass. Models: o4-mini (synthesis), Claude 3.7 Sonnet (judge), swappable via
  LiteLLM.

### 1.4 Reliability flag (must carry into any adoption)
Finch reported a **7.5×** phagocytosis effect where human re-analysis of the same data gave
**~1.75×**. Ensemble+consensus did **not** prevent a large over-report. Any BioMate adoption of
the pattern needs a human/rule guardrail before a finding is surfaced as quantitative truth —
directly relevant to CRO/IND (regulated) use.

### 1.5 BioMate gap analysis + integration path
| Robin component | BioMate today | Integrate how | Fit / licensing |
|---|---|---|---|
| **PaperQA2 grounded literature RAG** | `search_literature` MCP + `research_query` — but `research_query` is known to **confabulate real-but-unrelated PMIDs** (`[[project_research_confabulation]]`). No citation-graph RAG. | **Import `paper-qa` as a library** (Apache-2.0, LiteLLM, self-hostable; do NOT use Robin's Crow/Falcon wrappers — those need the paid Edison service). | **Strongest clean win.** Fixes a real existing reliability gap. |
| **Finch: N parallel trajectories → consensus finding** | BioMate executor is *stronger* for running pipelines (`run_code`, Nextflow DESeq2 on Batch, auto-loop QC) but auto-loop is **single-path remediation, not an ensemble**. | **Adapt the pattern** (reimplement N-trajectory + consensus over BioMate's own executor); Finch's code is Edison-gated → not importable. | Pattern, not code. Add the §1.4 guardrail. |
| **Hypothesis generation + LLM-judge tournament** | Campaign module ranks **quantitatively** (Bayesian opt over measured props); **no free-text hypothesis-gen + tournament upstream**. | **Import Robin's `robin/` generation + `prompts.py` + tournament** (Apache-2.0; generation/ranking need no Edison — only `data_analysis()` does). | **Highest-value directly-importable code.** Bolts onto the existing BO/DBTL campaign. |
| **Lab-in-the-loop orchestration** | Dry-lab engine; a separate SDL project exists (`[[project_self_driving_lab]]`). | Design inspiration only. | Architectural mismatch. |

**Verdict:** import PaperQA2 + Robin's generation/tournament modules (both Apache-2.0, no paid
dep); **adapt** the parallel-trajectory-consensus idea over our executor; the full "Robin
wholesale" is blocked not by license but by its best agents calling the **closed, paid Edison**
service.

---

## 2. WORK 2 — Nature Machine Intelligence: *capable models can outgrow collaboration*

### 2.1 Identity
*"Capable language models can outgrow the benefits of collaboration,"* **Nature Machine
Intelligence 8:1157–1172 (2026)**, DOI **10.1038/s42256-026-01268-y** (Google Research / MIT
Media Lab / UW). Full text paywalled; quantitative detail below is from the open abstract.

### 2.2 Core finding
Across **260 configurations × 6 benchmarks × 5 architectures × 3 LLM families** (compute, tools,
prompts held constant; only coordination structure + model capability varied):
- **Single-agent baseline performance is the most robust predictor** of whether coordination
  helps or hurts.
- There is a **capability-saturation threshold**: above it, more agents are unlikely to help and
  often degrade results ("noise injectors that reshape probability without improving decisions";
  **baseline-scaled error amplification**, cluster-robust P=0.030).
- The threshold predicts the *direction* of the multi-agent effect in **94%** of validation
  configs (SWE-bench Verified, Terminal-Bench); the fitted selector picks the best architecture
  in **87%** of held-out configs.
- Framed explicitly as a **per-domain selection rule, not a scaling law.**

### 2.3 The decision rule (verbatim implication)
1. Measure the single best model's **baseline on the specific task family**.
2. Below the domain threshold → collaboration adds complementary info → **use multi-agent**.
3. At/above threshold → **collapse to the single capable model**; multi-agent adds overhead +
   error-amplification risk.
4. Make collaboration **adaptive**, decided **per scenario** and **re-estimated per domain**.

### 2.4 Contrast data point (when multi-agent DOES win)
**Google "AI co-scientist"** (Gemini-based; Generation/Reflection/Ranking/Evolution/Proximity/
Meta-review tournament; https://deepmind.google/blog/co-scientist-...) wins on **hard,
open-ended, low-baseline** science (novel hypotheses, target discovery) — exactly the regime the
saturation rule says multi-agent should win. The two papers are consistent, not contradictory:
**co-scientist = low-baseline frontier; NMI = don't collaborate once saturated.**

### 2.5 Implication for BioMate
BioMate should **not** turn on blanket multi-agent. It should gate it:
- **Keep/enable multi-agent** for low-baseline, open-ended work: hypothesis generation,
  cross-domain experimental design, ambiguous multi-step planning, novel target triage.
- **Collapse to single strong model (or rules)** for near-saturated structured subtasks:
  intent→workflow routing, parameter extraction, unit/flag/enum mapping, structured report
  fill-in, deterministic QC-threshold checks. (This also matches BioMate's own documented
  **rule-first, LLM-fallback** doctrine.)
- **Reuse BioMate's own benchmark pass-rates** (param_prefill, routing, admet, pbpk, boin, …)
  as the per-domain baseline signal that sets each gate — the data already exists.

---

## 3. WORK 3 — Claude Code **dynamic workflows** & orchestration patterns

### 3.1 Dynamic workflow = orchestration-as-code
A workflow is a JS script that orchestrates subagents with a few primitives — `agent(prompt,
{label, schema})`, `pipeline(items, fn)` (ordered per-item fan-out), `parallel(tasks)`,
`phase(title)`. **Static** = fixed agent count/shape; **dynamic** = the script branches/loops on
prior results (`if`, `while`, vote/converge). The point (docs, verbatim): *"a workflow script
holds the loop, the branching, and the intermediate results itself, so Claude's context holds
only the final answer."* Runtime limits: up to 16 concurrent agents, 4,096 items/call, 1,000
agents/run; prompt-cache sharing across same-shape agents. Source:
https://code.claude.com/docs/en/workflows.md .

### 3.2 Pattern inventory + when each fits
| Pattern | Use when | Cost |
|---|---|---|
| **Single agent** | fits context; sequential/exploratory; back-and-forth | lowest |
| **Subagent / fork** | isolate high-volume or specialized work; return only a summary | medium |
| **pipeline** | ordered dependency chain (WGS→variant→annotate) | predictable |
| **parallel fan-out** | many *independent* items (N files/samples) → synthesize | medium-high |
| **adversarial verify** | one agent produces, another checks before reporting | +1 pass |
| **coordinator + roster** (API managed agents) | specialized agents with per-agent tools/MCP, persistent threads | high |

### 3.3 The anti-over-spawn rule (explicit in the docs)
*"Agent teams add coordination overhead and use significantly more tokens… For sequential
tasks, same-file edits, or work with many dependencies, a single session or subagents are more
effective."* Start 3–5; scale only with independent work; collapse to single agent for
sequential/exploratory. **This is the engineering twin of the NMI result** — both say: default
small, add agents only where the work genuinely decomposes and the single pass is weak.

### 3.4 Implication for BioMate
Codify BioMate's multi-step science as **dynamic workflows with explicit shapes** rather than an
all-or-nothing multi-agent pipeline: pipeline for dependent stages, parallel fan-out for
independent per-sample/per-candidate work, adversarial-verify for QC/findings, single agent for
saturated subtasks — chosen at runtime. (BioMate's own portfolio scheduler, slice 1–2, is
already the "parallel fan-out across campaigns" instance of this.)

---

## 4. BioMate today — what we actually have (file:line grounded)

### 4.1 Parallel *run* tracking — SOLID, do not rebuild
- **`RunStateStore`** (`backend/lib/galaxy/ai/runs/run_state_store.py`): Protocol + InMemory +
  Redis; `list_active_runs()` (:55-60,:120-125,:248-250), Redis `nextflow:runs:active` SET
  (:153), per-run hash, PID key, SETNX completion lock (:259-267); cross-worker by design.
- **`CompletionPoller`** (`.../runs/completion_poller.py:86-144`): per-worker daemon sweeps
  **every** active run (:170-183); AWS Batch `describe_jobs` authority (:244-271); idempotent
  across workers via `acquire_completion_lock` (:227). → Many concurrent runs are already
  tracked durably.

### 4.2 Frontend task surfaces — three, distinct
- **`TaskList`** (`frontend/client/src/components/task-list.tsx:1-182`) — sub-tasks of ONE AI
  reply (SSE/DOM events); not multi-run.
- **`WorkflowHistoryDialog`** (`.../workflow-history-dialog.tsx`) — the real multi-run list, but
  a **one-shot snapshot** (`/api/workflows/runs/overview`, no polling/SSE).
- **Per-run live panel** — one `EventSource` per invocation
  (`nextflow-workflow-viewer.tsx:2156`); no merged "all my runs" stream
  (`frontend/server/workflow-sse.ts:93` keys clients by invocationId).

### 4.3 Agent orchestration — a real multi-agent path exists but is DORMANT
- **Live path = single pass:** `classify_intent` returns the string `'agent_orchestrator'`
  (`ai_assistant.py:455,:523-525`) but `_handle_workflow_generation` (:552-568) calls
  `generate_workflow_unified(...)` (:560) — the *named* handler does not invoke the multi-agent
  class.
- **The orchestrator** (`backend/lib/galaxy/ai/agents/agent_orchestrator.py:46-292`): router →
  `DomainSpecialistPool` (**genuine parallelism**, `ThreadPoolExecutor max_workers=3`,
  `domain_specialist.py:114-155`) → assembler, with audit/learning services. Reachable only via
  `/api/ai_assistant/generate_workflow_multi_agent` → proxy `generateWorkflowMultiAgent`
  (`galaxy-api-proxy.ts:814-827`) which has **zero callers**. Wired end-to-end, never triggered.
- **No single-vs-multi chooser exists** anywhere.

### 4.4 Findings — deterministic single pass, no agents
`/api/nextflow/analyze-outputs` → `OutputAnalyzer.analyze` (`output_analyzer.py:37-101`,
rule-based by file type) → `FindingReporter` (one literature client) → `findings_report.md`.
No parallel/ensemble/agentic step.

### 4.5 Honest verdict
Already owned: **durable parallel run tracking + completion** and a **latent parallel-specialist
orchestrator**. Missing: **(i)** an aggregated *live* multi-run dashboard (pure UI glue over the
existing `active` SET + overview endpoint), and **(ii)** any runtime logic that *selects or
varies* agent patterns — the multi-agent path is dead code and findings are single-pass.

---

## 5. SYNTHESIS — making BioMate flexible & smarter

### 5.1 The unifying idea: a capability-gated **Pattern Router**
Introduce one decision point in the AI-assistant request path that, per task, picks an
orchestration shape — turning today's hardwired single-pass (and dormant always-parallel) into
an **adaptive** choice. The gate signal is BioMate's **own benchmark pass-rate** for the task's
domain (the NMI "baseline") plus task-shape heuristics (the Claude Code rule).

| Scenario (BioMate) | Baseline | Pattern | Why |
|---|---|---|---|
| intent→workflow routing, param extraction, unit/flag/enum, QC-threshold checks | high (saturated) | **single model / rules** | NMI: collaboration = noise above threshold; matches rule-first doctrine |
| workflow generation for a well-covered domain | high | **single pass** (today's unified) | already works; don't pay for agents |
| novel/ambiguous intent, cross-domain design, target triage, new-workflow synthesis | low | **revive the dormant parallel specialists** (router→pool→assembler) | NMI + co-scientist: multi-agent wins at low baseline |
| per-sample / per-candidate analysis, portfolio of campaigns | n/a (independent items) | **parallel fan-out** (pipeline/parallel) | Claude Code: independent work parallelizes; = portfolio scheduler |
| dependent pipeline (WGS→variant→annotate) | n/a | **pipeline** | ordered dependencies |
| findings on a completed run (esp. CRO/IND) | n/a | **ensemble trajectories → consensus → adversarial verify** | Robin Finch pattern + §1.4 guardrail |

### 5.2 Concrete, mostly-reuse build plan (priority order)
1. **Pattern Router (new, small):** a runtime chooser in the assistant path that selects
   single-vs-multi using benchmark baselines + task-shape rules, and **routes low-baseline
   intents to the already-built orchestrator** (`agent_orchestrator.py`). This *activates dead
   code* rather than writing a new engine — highest leverage, lowest new-code.
2. **Import PaperQA2 (`paper-qa`)** to replace/augment `research_query` and kill the
   PMID-confabulation gap. Library import, Apache-2.0.
3. **Ensemble-consensus findings layer:** extend `OutputAnalyzer`/auto-loop to run N analysis
   trajectories + a consensus meta-step + an adversarial-verify gate before a finding is shown
   (carry the Finch 7.5×-vs-1.75× guardrail; required for regulated outputs).
4. **LLM-judge tournament for hypothesis/target triage:** import Robin's `robin/` generation +
   tournament (Apache-2.0) as an upstream stage feeding the existing BO/DBTL campaign.
5. **Live multi-run dashboard:** UI glue over the existing `active` SET + `runs/overview` +
   per-invocation SSE — a merged "all my runs" view (the one genuinely missing UI). Pairs with
   the portfolio scheduler's parallel-campaign view.

### 5.3 Design guardrails (from the research)
- **Default small.** Single model/rules unless the baseline gate says collaboration helps
  (NMI 94% rule; Claude Code anti-over-spawn).
- **Re-estimate thresholds per domain** from benchmark history; don't globalize.
- **Collaboration must earn its cost** — above saturation it amplifies errors.
- **Every agentic finding needs a verify/guardrail** before it's surfaced as quantitative truth.
- **Reuse, don't rebuild:** run-state tracking, the specialist pool, the executor, and auto-loop
  already exist — the work is *selection logic + targeted imports + one UI*, not a new platform.

---

## 6. Caveats (honest)
- **"Science" vs. reality:** the virtual-pharma system is Robin (arXiv/Nature), **not a *Science*
  paper**; confirm with the user if a strict *Science* source was meant.
- **NMI full text paywalled:** the 5 architectures / 4 of 6 benchmarks / 3 model families are not
  in open sources — do not cite specific names as from that paper without the PDF.
- **Robin numbers** (551 papers, 7.5×, ABCA1 p-value) are from the arXiv rendering/secondary
  summaries — spot-check against the PDF before external use.
- **Robin "wholesale" is not importable** — its best agents call the closed, paid Edison service;
  only the open substrate (PaperQA2/Aviary) + generation/tournament modules are reusable.

## 7. Sources
Robin arXiv 2505.13400 · github.com/Future-House/robin · PaperQA2 arXiv 2409.13740 ·
github.com/Future-House/paper-qa · Aviary arXiv 2412.21154 · NMI DOI 10.1038/s42256-026-01268-y ·
Google AI co-scientist deepmind.google/blog/co-scientist · Claude Code workflows
code.claude.com/docs/en/workflows.md, sub-agents.md, agent-teams.md · BioMate file:line cites in §4.
