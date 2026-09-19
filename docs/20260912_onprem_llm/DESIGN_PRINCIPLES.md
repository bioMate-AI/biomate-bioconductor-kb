# Design principles — what the model learns vs. what the harness does

**2026-09-19.** Established during design review. These govern the data/model prep so we build a
*general, flexible* model and avoid overfitting to today's engineering.

## 1. Separation of concerns: judgment in weights, mechanism in harness
The product already implements deterministic, tunable engineering. **Do NOT bake it into the model.**

| Belongs in the HARNESS (deterministic, tunable) | Belongs in the WEIGHTS (semantic judgment) |
|---|---|
| Retriever scores + 0.15 near-tie threshold | Pick the best-fitting workflow from candidates |
| Disambiguation gate / card ("which best fits?") | Recognize a genuinely under-specified request |
| Workflow panel: full param configuration/override | Param **prefill with restraint** (only what's implied) |
| Schema defaults, "ensure gold present" | Clarify only **essential blocking inputs** (data/reference) |
| Candidate presentation / ranking display | Decompose into a valid phase→step / cross-workflow DAG |

**Rule:** the system's division of labor *informs which skills to teach*; the data must *not encode the
mechanism* (threshold values, card format, "produce a complete config"). Coupling weights to
engineering is brittle, untunable, wastes capacity, and is the core **overfitting** failure mode.

## 2. Clarification is ONE cross-cutting function, not a siloed task
"Resolve-or-ask" spans intent/routing (ambiguous → the harness presents options), parameters
(essential input missing → ask), and decomposition. Teach it as one general judgment woven across
contexts — this also *reduces* overfitting vs. many rigid per-task templates.

## 3. Restraint, because the panel finishes the job
The workflow panel provides full configuration/override and defaults cover most knobs. So the model:
- **prefills only user-specified/overridden params** (never restates defaults),
- **clarifies only genuine blocking inputs** (data/reference/genome), not every schema-required knob,
- **presents/defers** on ambiguity rather than forcing false confidence (harness owns the presentation).

## 4. Near-ties: credit, don't force
When retriever scores are within 0.15, the harness surfaces the alternative. In the data we record
`acceptable_alts` as **eval metadata** (so scoring credits a defensible near-tie) — never as a training
target that would teach the model to reproduce a score threshold.

## 5. Anti-overfitting checklist (applies to every generator)
- Diverse surface forms (paraphrase layer), not one template.
- Ground in real artifacts; request must not name the target (teach understanding, not lexical match).
- No mechanism/threshold/format baked into targets.
- Don't over-iterate the data pipeline: land generator fixes, then ONE consolidated regeneration —
  not repeated piecemeal regenerations that fit transient states.

## Code reflecting these
- `build_rag_routing_sft.py` — single semantic gold + `acceptable_alts` (eval metadata); no baked threshold.
- `generate_clarification.py` — clarify essential blocking inputs only (panel/defaults handle the rest).
- `generate_conditional_param.py` / `generate_param_data.py` — restraint + `schema_guard` type/enum.
- `generate_decomposition_data.py` — valid DAG deps (immediate predecessor).
