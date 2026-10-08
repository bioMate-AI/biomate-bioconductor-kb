# Agent Patterns — Research Notes & BioMate Integration Plan

**Date:** 2026-10-08
**Scope:** Detailed notes on three external works + a grounded map of BioMate's own
orchestration, answering: *how do we make BioMate more flexible and smarter?*
**Lens throughout:** what we have · what we lack · what we can directly integrate.

---

## 0. Thesis (the one-paragraph answer)

Massive hierarchical multi-agent fan-out — the pattern behind Stanford's "virtual pharma" system
(**The Virtual Biotech**, ~37,000 agents) — is **one** agent pattern, not *the* pattern. The Nature Machine Intelligence result shows
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

## 0.1 CORRECTION (2026-10-08) — BioMate already has most of these primitives

An initial draft of this doc proposed *importing* PaperQA2 and *building* an
ensemble-consensus/verify layer. **Both were wrong — BioMate already has them.** A direct
capability audit (grep + module reads, file:line below) found:

- **Grounded literature RAG is already in BioMate.** `/api/ai_assistant/paperqa_synthesize`
  wraps PaperQA2 (`from paperqa import Docs, Settings`, `paper-qa>=5.0.0`) in
  `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:6113-6203`; exposed as the
  `synthesize_papers` tool (`frontend/server/orchestrator.ts:135,266`); plus a `ResearchAgent`
  over PubMed/arXiv/Semantic Scholar (`backend/lib/galaxy/ai/agents/research_agent.py:1-20`), an
  offline FTS5 literature index (`backend/lib/galaxy/ai/local_literature.py`), intent-routing to
  the research path, and an e2e test (`frontend/e2e/research-paperqa-flows.e2e.ts`). **Nothing to
  import.**
- **Inference-time ensemble + verification is already in BioMate** as model-agnostic primitives:
  `backend/lib/galaxy/ai/verification_layer.py` — `majority_vote`/`self_consistent` (sample K →
  modal answer + confidence), `consensus` (N independent answers agree?), `verified_sample`
  (pass@k oracle), `grounded_pick` (reject off-catalog). Its own docstring states BioMate's
  thesis: *"The moat is the harness, not model size… grounded, executed, and VERIFIED. Our QC
  auto-loop already is 'verifiable rewards'."* **This is the §5.2 'ensemble-consensus findings'
  idea — already built; the work is WIRING it into the findings path, not building it.**
- **De-novo generation exists** (`backend/lib/galaxy/ai/drug_discovery/generators.py`: BRICS +
  BioNeMo) feeding the generate→predict→score→rank loop.

**The corrected framing (this is the real answer to "make BioMate smarter"):** BioMate is *not*
missing these capabilities. It has grounded RAG, consensus/verification primitives, de-novo
generation, a dormant parallel-specialist orchestrator, and durable parallel run-tracking. What
it lacks is the **adaptive SELECTION layer that chooses which primitive/pattern to use per
scenario and wires them together** — exactly the capability-gated Pattern Router of §5.1. The
tables/plan in §1.5 and §5.2 below are corrected inline, but treat §5.1 (selection) + §4.5
(live multi-run UI) as the genuine gaps, and **everything else as wiring existing parts, not
importing/building new ones.** Lesson recorded: audit BioMate's own capabilities before
proposing any external import or new build.

---

## 1. WORK 1 — "Virtual pharma": Stanford **The Virtual Biotech** (~37,000 agents)

### 1.1 Identity
- **Title:** *The Virtual Biotech: A Multi-Agent AI Framework for Therapeutic Discovery and
  Development.* Lead: **Harrison Zhang**; PI: **James Zou** (Stanford Biomedical Data Science /
  SAIL / CZ Biohub; lab **GXL**, gxl.ai).
- **Venue:** **Science, 17 Sep 2026.** DOI **10.1126/science.aeg6779**
  (https://www.science.org/doi/10.1126/science.aeg6779, paywalled). Preprint: bioRxiv
  https://biorxiv.org/content/10.64898/2026.02.23.707551v1 . Stanford Medicine press:
  https://med.stanford.edu/news/all-news/2026/09/virtual-biotech-company.html .
- **Open-source:** the supporting literature tool **Paperclip** is confirmed open
  (**https://github.com/GXL-ai/paperclip**, **Apache-2.0**). The full 37k-agent orchestration
  framework is *asserted* public in press materials but a canonical repo/license was **not
  verified** — the Science Data/Code Availability statement (paywalled) is authoritative; **check
  it before any build decision.**
- **Do-not-confuse:** *PharmAgents* ("Building a Virtual Pharma with LLM Agents", arXiv
  2503.22164) — a small handful of agents, NOT this paper.
- The "~35,000" figure is **~37,000** (see §1.3).

### 1.2 What it does
Emulates a whole pharma company end-to-end from a natural-language query: target ID/validation →
safety → drug-delivery/modality → clinical-trial review. **Results:** analyzed ~37–50k clinical
trials in **~6 hours**; found that drugs targeting **"switch-like," cell-type-specific (bimodal)
genes** are **~40% more likely to advance Phase 1→2, ~48% more likely to reach market, with ~32%
fewer adverse events**; and — using **only pre-2025 data** — autonomously designed a **B7-H3
(CD276) ADC for lung cancer** matching **ifinatamab deruxtecan** (FDA Breakthrough Therapy, Aug
2025). That convergence is the headline external validation.

### 1.3 Collaboration architecture AT SCALE (the crux — a *different* pattern from Robin)
- **Hierarchical delegation, not a market or emergent society:** a virtual **CSO** agent → **4
  research divisions** → **~11 "principal" agents** (stat-genetics, functional genomics, disease
  biology, cheminformatics, clinical-data, …) with **100+ tools** + Open Targets /
  ClinicalTrials.gov / ChEMBL → spawned **ephemeral worker agents**. **Independent reviewer/critic
  agents gate each stage** before results propagate; agents **debate** to stress-test.
- **Where "37,000" comes from:** **map-reduce fan-out of ephemeral workers**, ≈ one agent per
  unit of a big corpus (e.g. **37,075 Phase II/III trial outcomes**, one agent each) → each emits
  a compact result → reduced upward. It is **NOT** 37k persistent roles — it's horizontal data
  parallelism. The persistent org is small (~11 principals + CSO + reviewers).
- **Scale enabler = Paperclip (Apache-2.0):** exposes **8M+ biomedical papers as an AI-native
  virtual filesystem** navigated with bash tools (`ls`/`grep`/`cat`/`find`) + parallel
  sub-agents. Reported **1.6× more accurate, 2.4× faster, 3.6× cheaper than MCP-based retrieval**;
  claimed >1 order-of-magnitude time/cost cut for the whole system.
- **LLM/compute:** Claude (Anthropic) models, designed model-agnostic; 37k-trial sweep ~6 h.
  **Exact models, token/$ cost, compute are NOT disclosed** publicly (in the paywalled Methods/SI).

### 1.4 Evidence & honest limits
Validation is **retrospective + external convergence**, not in-house wet-lab: B7-H3 is a single
anecdote matching an independently-advanced drug (hindsight/selection-bias risk); the trial-success
feature is a **correlational** data-mining result; cost/compute undisclosed. "37k agents" is
**throughput/parallelism**, not 37k reasoning roles — the genuine novelty is the small org +
reviewer gates + Paperclip + massive fan-out. Any adoption of agentic findings still needs a
verify gate before quantitative claims (cf. the regulated CRO/IND path).

### 1.5 BioMate integration — assessed AGAINST what BioMate already has (§0.1 discipline)
| Virtual-Biotech element | BioMate today | Integrate how | Honest fit |
|---|---|---|---|
| **Paperclip (papers-as-filesystem + map-reduce extraction)** | BioMate **already has grounded literature**: PaperQA2 synthesis (`ai_assistant.py:6113-6203`), `ResearchAgent` (PubMed/arXiv/S2), offline FTS5 index (`local_literature.py`). The known weak path is `research_query` PMID confabulation (`[[project_research_confabulation]]`). | **EVALUATE, don't auto-import.** Benchmark Paperclip's filesystem+fan-out retrieval *against our existing PaperQA2/FTS5 stack* on our own queries. Adopt only if it measurably beats what we have (its MCP-vs-filesystem win suggests it *might* for large-corpus novelty checks). Apache-2.0 makes a PoC clean. | Candidate PoC — **not** a decided import. (Lesson from the PaperQA mistake: verify vs existing first.) |
| **CSO→divisions→principals→ephemeral-workers hierarchy + reviewer gates** | BioMate has a **dormant** router→parallel-specialists→assembler orchestrator (`agent_orchestrator.py`) + consensus/verify primitives (`verification_layer.py`) + a QC auto-loop ("verifiable rewards"). | **WIRE/activate:** wake the dormant orchestrator and add **reviewer-agent gates** using the EXISTING `verification_layer` + QC-loop. The paper validates this exact shape at scale. | Mostly activating existing parts. |
| **Map-reduce fan-out over large record sets (per-trial / per-paper / per-compound)** | BioMate's **durable cross-worker run-tracking** (`RunStateStore`/Redis + `CompletionPoller`) already coordinates many parallel units + aggregation. The portfolio scheduler (slice 1–2) is the campaign-level instance. | **WIRE:** express large sweeps as fan-out over the existing run-tracking substrate. | Reuses existing infra. |
| **"Switch-like / bimodal target gene" success heuristic** | Campaign target-triage uses quantitative scoring; no such prior encoded. | **Adopt as a scientific PRIOR** in target triage; cite/benchmark against it. | Usable, cheap, high-value prior. |
| **Full 37k-agent "virtual company" simulation** | — | **Inspiration only.** Keep BioMate's deterministic, auditable, reproducible execution; borrow coordination + the prior, not free-form self-organization at 37k scale. | Research demo, not a platform feature. |

**Verdict:** The Virtual Biotech is the **validation at scale of the exact architecture BioMate
already has dormant** (hierarchical router → parallel specialists → assembler, + reviewer gates +
massive fan-out over run-tracking). So the headline paper argues for **activating and wiring what
we own**, not importing a new engine. The one genuinely new external artifact worth a bounded PoC
is **Paperclip** — and even that must be benchmarked against our existing PaperQA2/FTS5 stack
before adoption. Keep deterministic execution as the moat; borrow the coordination pattern, the
reviewer gate, and the bimodal-target prior.

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
| findings on a completed run (esp. CRO/IND) | n/a | **ensemble → consensus → reviewer/verify gate** (wire `verification_layer`) | Virtual-Biotech reviewer gates + §1.4 guardrail; primitives already exist |

### 5.2 Concrete, mostly-reuse build plan (priority order)
**All items below are WIRING existing BioMate parts into an adaptive selection layer — not
importing or building new capabilities (see §0.1). The two genuine gaps are #1 and #5.**
1. **[GENUINE GAP] Pattern Router (new, small):** a runtime chooser in the assistant path that
   selects single-vs-multi using benchmark baselines + task-shape rules, and **routes
   low-baseline intents to the already-built orchestrator** (`agent_orchestrator.py`). Activates
   dead code; highest leverage, lowest new-code.
2. ~~Import PaperQA2~~ — **WRONG / already integrated** (§0.1). No action beyond optionally
   routing more queries through the existing PaperQA-grounded path.
3. **[WIRE existing] Ensemble-consensus findings:** call the EXISTING `verification_layer.py`
   primitives (`self_consistent`/`consensus`/`verified_sample`) from the findings/auto-loop path
   + a verify gate before a finding is shown (carry the §1.4 7.5×-vs-1.75× guardrail). The code
   exists; it just isn't wired into `output_analyzer.py` yet.
4. **[VERIFY FIRST] Hypothesis/target triage ranking:** BioMate already has `generators.py`
   (de-novo) + `bayesian_optimizer.py` (quantitative ranking) + an LLM-judge pattern elsewhere —
   **audit whether a free-text hypothesis-tournament stage is truly absent before building one.**
   Do not assert this is a gap without checking (the PaperQA mistake).
5. **[GENUINE GAP] Live multi-run dashboard:** UI glue over the existing `active` SET +
   `runs/overview` + per-invocation SSE — a merged "all my runs" view. Pairs with the portfolio
   scheduler's parallel-campaign view.

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
- **Capability audit beats assumption:** the first draft wrongly proposed importing PaperQA2 and
  building a consensus layer — both already exist in BioMate (§0.1). **Audit BioMate before
  proposing any import/build.** This applies to the open §5.2 #4 claim too (verify before asserting).
- **Virtual Biotech full text paywalled** (Science): exact models, token/$ cost, compute, and the
  canonical open-source repo/license for the full framework are **not in open sources** — read the
  Methods/SI + Data/Code Availability before any build decision. Numbers (37,075 trials, +40/48/32%,
  B7-H3) are from the preprint/press — spot-check against the paper before external use.
- **"37,000 agents" = parallel fan-out, not 37k roles** — don't over-read the headline.
- **NMI full text paywalled:** the 5 architectures / 4 of 6 benchmarks / 3 model families are not
  in open sources — do not cite specific names as from that paper without the PDF.
- **Paperclip = evaluate, not adopt:** benchmark it against BioMate's existing PaperQA2/FTS5 stack
  before any integration.

## 7. Sources
**The Virtual Biotech** — Science DOI 10.1126/science.aeg6779 · bioRxiv 2026.02.23.707551 ·
med.stanford.edu/news/.../virtual-biotech-company.html · Paperclip github.com/GXL-ai/paperclip
(Apache-2.0) · (do-not-confuse: PharmAgents arXiv 2503.22164) · **NMI** DOI
10.1038/s42256-026-01268-y · Google AI co-scientist deepmind.google/blog/co-scientist · **Claude
Code** code.claude.com/docs/en/workflows.md, sub-agents.md, agent-teams.md · BioMate capabilities
file:line in §0.1 + §4. (Robin — arXiv 2505.13400 — surveyed but NOT the intended paper.)
