# Design — Better Task Decomposition/Orchestration + a Real Instruction-Panel Feedback Loop

**Date:** 2026-10-19
**Status:** design + build plan (follows the verified-state digs; no new primitives assumed)
**Grounding:** `docs/20261019_BIOMATE_CURRENT_STATE_REVIEW.md` + two code-verified digs (decomposition/orchestration; instruction-panel feedback). The unifying finding: BioMate's advanced machinery is **built but dormant/unwired**; the live product is a lean single-pass + linear-chain pipeline. So "better" at both = **activate + improve built machinery, measured by a verifier, adopted through a gate** — not new primitives.

---

## Part A — Task decomposition + orchestration across flow patterns

### Verified current state
- **Live:** single-workflow generation (dominant; the composer even *collapses* multi-step asks to one workflow). Genuinely robust **linear chain execution** (`workflow_chain.py::_run_chain`: real output→input handoff, type checks, polling, resume, reconciliation). Live "decomposition" = an LLM classifier (`galaxy-assistant.ts::analyzeIntent`) emitting single/sequential/multi flags + a **linear** `pipeline_steps` plan + regex collapse-overrides + a `chainHint` lookup vs curated `workflow_chains`.
- **Built but doesn't fire from chat:** a production-grade **parallel/DAG engine** (`_run_dag_chain` + `galaxy.chain.dag.run_plan`, `max_parallel`) — API-reachable, but chat never emits `depends_on` plans; `decomposed_dag.build_dag_plan` (emits exactly those plans) is behind a no-op flag; `pattern_router` (baseline-pass-rate → single vs multi-specialist) and the multi-agent orchestrator are dormant/zero-caller.
- **Measurable:** a real decomposition benchmark — `node_f1` / `edge_f1` / `structure_accuracy` over **262 gold rows** (`decomposition_v2` + `decomposition_real`).

### Design
1. **A decomposition harness in the live path that emits DAG plans when a goal is genuinely parallel/branching** — reuse `decomposed_dag.build_dag_plan` so the *already-built* parallel engine fires. This is the exact shape of the **deep-research controller** (`grounded-prototype/research/controller.py`: decompose→route→parallel/sequential→orchestrate), repointed at workflow DAGs. Keep the collapse guard (don't over-decompose); make the single-vs-chain-vs-DAG decision **verifier-informed**, not an LLM flag alone.
2. **A real pattern selector** (single / linear chain / parallel DAG / iterative-QC / research) — the flow pattern is a *harness choice*; select it with the blind, verifier-informed logic (Harness2-style) rather than the regex-collapse heuristics.
3. **Measure on `node_f1`/`edge_f1`/`structure_accuracy`** (the 262 gold rows) + end-to-end task success. Goal = decompose *correctly* (parallel when parallel), not *more*.
4. **Model-robust:** the DAG engine's type-compat checks are deterministic; the LLM only *proposes* a plan that is validated. Lifts Gemini Flash / Claude / local 9B equally.

### What this is, honestly
Mostly **wiring the live composer to the built DAG machinery** + improving decomposition quality against an existing benchmark. The orchestration *engine* already exists and is excellent; the gap is that chat never drives it with a branching plan.

---

## Part B — A real instruction-panel feedback loop

### Verified current state
- **Live (next-turn only):** standing project instructions (`researchGoal`), "Make instruction" → `project_instruction` rows, request-scoped composer instructions — all injected into the prompt. ("Save to notes" is captured but hidden from the model.)
- **Built but drives nothing:** two complete **correction-capture backends** (Python `workflow_user_corrections` + a learning service that updates router keywords/preferences; TS `correction_log`) — but **no shipped UI posts to either**, and the TS "Recent Corrections (avoid these mistakes)" prompt-injection is **dead code**. A fully-plumbed **regulatory-document DPO → weekly adapter retrain** loop exists but is **disabled at its only mount** (`recordEditPairs={false}`), learning nothing.
- **No feedback→reward or feedback→harness-edit loop** beyond that dormant DPO.

### Design (three layers, smallest-first)
1. **Immediate (wire what's built):** the instruction panel / workflow cards POST corrections to the *already-built* endpoints, and **revive the dead injection** (`buildMemoryContextPrompt`'s "Recent Corrections") into the live `addMemoryHints`, so a correction steers the next turn. Pure wiring of existing code.
2. **Durable (the missing closed loop — the novel piece):** treat a correction as a **verifier/reward signal** — a correction *is* the right answer, so it is **answer-based** ground truth. Feed it into the **gated Harness2 improve loop** (`grounded-prototype/research/`): corrections become durable **rule/skill edits**, proposed → probed (does the edit make the model produce the corrected answer?) → **human-reviewed before adoption**. This generalizes the regulatory-DPO template from IND-only to every correction channel.
3. **Control surface:** the instruction panel = *instructions* (steer now) + *corrections* (learn durably) + a **gated review** of proposed harness edits derived from feedback.

### Build order (this doc's first increment, in-worktree, tested)
- **B2 bridge first** (self-contained, testable, and the piece that *doesn't exist*): `research/feedback.py` — a `Correction` type + a `CorrectionVerifier` (answer-based: reward = did the response match the user's corrected value / avoid the original mistake) that plugs into the P0 verifier bridge + the Harness2 improver, so a correction drives a **gated** harness edit. Tests prove: a correction yields a reward signal; it drives a proposed (not auto-applied) harness edit; the gate blocks adoption until approved.
- Then the UI/endpoint wiring (B1) + reviving the dead injection — real frontend/backend edits that need the live stack to verify, documented for a gated dev run.

### What this is, honestly
Mostly **wiring built-but-unwired capture + reviving dead code** (B1), plus **one genuinely new loop** (B2: corrections → gated harness improvement via the Harness2 substrate already built). Not new primitives.

---

## Cross-cutting: the program
Both parts are the same move — **activate dormant machinery, measure with a verifier/benchmark, adopt through a gate** — and both plug into the substrate already built this session (deep-research controller for decomposition/orchestration; verifier bridge + Harness2 improver for feedback→improvement). Model-robust throughout. All improvement runs are **offline + gated**; nothing self-rewrites the live scaffolding.

**Start:** Part B2 (the correction→gated-improvement bridge) — clearest built-but-missing loop, fully testable without the live stack, and it directly reuses the P0/P1 + Harness2 work.
