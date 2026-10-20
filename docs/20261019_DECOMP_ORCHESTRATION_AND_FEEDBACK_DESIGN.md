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

### Built this increment (A-core, in-worktree, tested offline)
`grounded-prototype/research/decompose.py` + `research.verifiers.StructureVerifier` — the **harness-owned decider** that is the actual missing piece:
- **`infer_edges` / `build_plan`** — the LLM proposes sub-tasks (with optional `produces`/`consumes` I/O tokens); the harness infers dependency edges deterministically (a node depends on an earlier node whose output it consumes) and **defaults to PARALLEL when no handoff is evident** — the exact correction for the live over-collapse. Emits the benchmark/engine plan shape `[{sub_task, order, depends_on}]`, so it drops straight into `galaxy.chain.dag.run_plan`.
- **`validate_plan`** — deterministic guardrails the DAG engine assumes (acyclic, orders resolvable, no dangling/self edge), raising *before* the engine runs.
- **`select_pattern`** — QC-loop goal → `ITERATIVE_QC`; single node → `SINGLE`; else the plan's own topology (`parallel`/`sequential`/`mixed`). The pattern is a property of the graph, not an LLM flag.
- **`StructureVerifier`** — mirrors `evaluation/datasets/decomposition_v2/score.py::score_one` (node_f1 + edge_f1 + structure match), routed by `select_verifier` on a `gold_subtasks` ground-truth shape, so decomposition plans score the same way the real benchmark scores them and plug into the gated Harness2 improver.
- **Tests** (`tests/test_decompose.py`, 18/18): independent tasks → parallel (over-collapse fix); handoff → sequential edges; fan-in → mixed; single/QC overlays; cycle/dangling/self-dep rejection; injectable LLM `depends_fn`; exact plan scores >0.9 and strictly beats a collapsed-to-parallel answer; verifier-bridge routing.

### A-live — concrete wiring spec (code-verified 2026-10-20; needs a gated dev run, NOT shipped blind)

Two code-maps established that **the DAG path is already wired end-to-end** and the only gap is the Node composer dropping dependency info:

- **Downstream is DAG-ready, no change needed:** `chain-execution.ts::buildChainSubmitSteps` already forwards `depends_on` (reads `s.depends_on`), `submitWorkflowChain` sets `isDag = steps.some(s => s.depends_on != null)`; the Node proxy `routes.ts POST /api/workflows/chain` passes `depends_on`/`connections`/`max_parallel`; the backend `workflow_chain.py::submit_chain` auto-detects `is_dag = any(step.depends_on is not None)`, validates via `dag.validate_plan`, sets `execution_mode='dag'`, and `_run_chain` forks to `_run_dag_chain`→`dag.run_plan` (parallel waves, `max_parallel` slots). `PipelineListView` already renders `dependsOn: s.depends_on`.
- **The one gap:** `galaxy-assistant.ts::processSequentialPipeline` builds `pipeline_steps` with a linear `input_from` (string ref) and **no numeric `depends_on`**; the non-sequential multi-intent branch emits a *primary + additional cards*, never a single concurrently-executing plan. `analyzeIntent` already carries `dependsOn` per intent but as **string ids**, and it's dropped at assembly.

**The hazard that forbids a naive flip:** DAG execution resolves cross-step artifacts via typed `connections` (`dag.bind_inputs`), which the Node composer cannot emit (it has no `type_provider`). Flipping an existing **sequential** chain to `execution_mode='dag'` without connections would break artifact handoff. The Python `decomposed_dag.build_dag_plan` is the component that derives `connections` correctly (via `type_provider`), but it's Node-external and flag-gated (`BIOMATE_MULTITASK_DAG_ENABLED`, no live callers).

**Safe, correct first slice (the over-collapse fix, matches `decompose.py`):** emit a DAG plan **only for the independent-roots case** — multiple runnable intents with no data handoff → every step `depends_on: []`, `connections: []`, `execution_mode: 'dag'`, `max_parallel: n`. `validate_plan` passes (roots need no connections) and `run_plan` fans them out concurrently. Sequential/mixed chains that need typed handoff stay on the existing (working) legacy path untouched until the connections story is solved (either port `type_provider` to Node, or route multi-step generation through the Python `build_dag_plan` + `to_pipeline_card`).

**Exact changes for the slice:**
1. `galaxy-assistant.ts`: in the non-sequential multi-intent branch (≈5519-5544), when ≥2 `isRunnableWf` results and the intents are independent, assemble a `workflow_type:'pipeline'` card whose `pipeline_steps` each carry `depends_on: []` + `execution_mode:'dag'` + `max_parallel`, instead of primary+additional cards. Map `intent.dependsOn` (string ids → 1-based step numbers) for any declared edges; drop to the safe parallel-roots plan when any edge would require a connection the composer can't type.
2. No downstream change (passthrough already proven). `submit_chain` auto-detects DAG.
3. Keep all three collapse overrides (regex ≈3415-3449; Tier-1 coverage ≥0.8 ≈5090; same-path merge ≈5356) — they must still be able to collapse a genuinely single-workflow ask.

**Verification (the gated dev run, mandatory before "done"):** per the UX E2E Completeness Standard — screenshot-audit all 6 reference use-cases (ADMET/RNA-seq/WGS/CryoEM/CRO/IND) for correct pre-run/running/completed states in BOTH panels, confirm a real idle→running→completed SSE transition on a parallel plan, and confirm sequential chains still hand off artifacts correctly. Offline: measure the plan emitter on the 165 `decomposition_v2` + 68 `decomposition_real` gold rows with `StructureVerifier` (the A1 harness logic ported to the composer's decision). Do NOT mark A-live done on a code review alone.

**Status:** the offline decider (`research/decompose.py` + `StructureVerifier`, A1) encodes the correct parallel-vs-sequential logic and is tested (18/18). The live edit above is a central-chat-UX change on an expensive path; it is specified and ready for a dedicated gated dev-run session, not shipped from this offline worktree.

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

### B1 DONE (code-verified 2026-10-20, commit on grounded-harness2)
Mapping the live surface corrected the plan in two useful ways:
- **"Revive the dead injection" is already solved.** `galaxy-assistant.ts::_buildCorrectionContextBlock` is **live** (invoked in the first-message `Promise.all`, prepended to the system prompt) and reads `getUserCorrections` from `correction_log`, formatting "Prefer <to> over <from>". The dead `buildMemoryContextPrompt` "Recent Corrections" block is redundant with it — reviving it would **double-inject**, so it stays retired. The real gap was only the missing UI write.
- **The UI now writes a correction.** `lib/corrections.ts` + the disambiguation `onSelect` POST a structured correction to the existing `/api/memory/user/corrections` → `correction_log`, which the live injection reads next turn. The signal is non-fabricated (suggested = the backend's own highest-`score` candidate; corrected = the user's differing pick). Unit-tested 7/7; tsc clean; full vitest 1877 pass.
- **Canonical stack decision:** the **TS `correction_log`** stack is canonical for chat corrections (it already has the live read-back). The Python `workflow_user_corrections` stack (+ learning service) stays for the multi-agent generate path; the two are not merged here. Two backend flags noted for a later pass: `workflow_user_corrections` has no production CREATE/migration (only tests create it), and `workflow_learning_service` queries `'domain_correction'`/`'tool_correction'` while writes use bare `'domain'`/`'tool_selection'` (silent-miss risk).
- **Remaining (gated dev run):** browser UX-audit of the disambiguation-pick → correction → next-turn-injection round-trip on dev; optionally extend capture to param-override and candidate-reselect-in-panel.

### What this is, honestly
Mostly **wiring built-but-unwired capture + reviving dead code** (B1), plus **one genuinely new loop** (B2: corrections → gated harness improvement via the Harness2 substrate already built). Not new primitives.

---

## Cross-cutting: the program
Both parts are the same move — **activate dormant machinery, measure with a verifier/benchmark, adopt through a gate** — and both plug into the substrate already built this session (deep-research controller for decomposition/orchestration; verifier bridge + Harness2 improver for feedback→improvement). Model-robust throughout. All improvement runs are **offline + gated**; nothing self-rewrites the live scaffolding.

**Start:** Part B2 (the correction→gated-improvement bridge) — clearest built-but-missing loop, fully testable without the live stack, and it directly reuses the P0/P1 + Harness2 work.
