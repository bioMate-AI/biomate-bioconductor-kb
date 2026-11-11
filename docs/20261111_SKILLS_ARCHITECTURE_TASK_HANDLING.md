# 2026-11-11 — Skills architecture for task-pattern handling, decomposition & operations

**Thesis (from the 2026-11-10/11 demo review):** post-decomposition solution-selection is
not retrieval, intent is not keyword-matchable, and a closed solution-type enum can't be
exhaustive. The right mechanism is **skills** — named, described, independently-authored
procedures the agent selects by *inference over their descriptions*, composes, and falls
back from (synthesize/ask) when none fits. This doc grounds that in BioMate's existing
skills framework and lays out the extension + migration.

## 0. What exists today (don't reinvent)

BioMate already has a skills framework — two layers:

- **`skill_manager.py` (`SkillManager`)** — expert-role skills: `backend/lib/galaxy/ai/skills/*.md`,
  YAML frontmatter + Markdown body (`ml-bioinformatics.md`, `drug-discovery-chemist.md`,
  `multiomics-integrator.md`, …). Composable, user-selectable, auto-detected. They **inject
  domain expertise into the system prompt**.
- **`agents/skill_loader.py` (`SkillLoader`)** — maps `INTENT_TO_SKILLS[intent_type] → skill
  prompts` (claude-scientific-skills: workflow steps, templates, best practices), augmenting
  the response.

**Gaps that make these insufficient for the demo failures:**
1. **Selection is keyword triggers.** Frontmatter `triggers: [model training, fine-tuning, …]`
   → `detect_skills()` substring/regex match. This is the exact keyword-matching rejected in
   the demo review (`_TRAIN_VERBS`, "specialize"). The parser already *accepts* a `description`
   field as an alternative (`skill_manager.py:85`), but selection is trigger-driven, not
   inference-driven.
2. **Skills only augment the prompt.** They change *how Claude writes*, not **how a task is
   decomposed**, **which solution/engine it routes to**, or **how the result is presented**.
   Decomposition stays in the ~400-line monolith (`galaxy-assistant.ts:6799–7160`); routing
   stays nearest-catalog-retrieval (`_resolve_task_to_workflow`); presentation stays the flat
   `to_pipeline_card` (`decomposed_dag.py:96`).
3. **No task-pattern skills.** Sequential / parallel-independent / fork-join / fan-out are
   prose sections in the monolith (`:7130` Branch-and-integrate, `:7151` Sequential) and all
   collapse to one flat step list — the per-pattern presentation gap.

## 1. The three skill categories (the extension)

| Category | Owns | Examples | Today |
|---|---|---|---|
| **Pattern skills** | recognition of a task *shape* → decomposition structure (steps + edges) **+ the presentation contract for that shape** | `single`, `sequential-chain`, `parallel-independent`, `fork-join`, `fan-out-rank` | prose in the monolith; flat card |
| **Operation skills** | what a *kind of work* needs → inputs, params, which engine/workflow, **and its own card** | `generator-adaptation`, `predictor-retraining`, `multi-omics-integration`, `target-id-evidence`, `docking`, `de-analysis` | partly: domain prompt skills + feature-flagged `route_*_result` "ADD a route" shims |
| **Expert-role skills** (exists) | reasoning persona / methodology guidance | `ml-bioinformatics`, `drug-discovery-chemist` | ✅ already injected into the prompt |

Operation skills are grounded, not arbitrary: they **are** the documented SYSUCC capabilities —
Models → Train / Adapt / Optimise (BD doc `20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_EN.md`
§5.4) and the "three kinds of learning" (§7.3: predictor retraining, generator adaptation,
knowledge adaptation).

## 2. Selection = inference over descriptions (not triggers)

- Each skill's frontmatter carries a `description` written as **when-to-use** (what the task
  must *mean* for this skill to apply), not a keyword list.
- The decomposer/router is given the set of skill descriptions and **infers** which skill(s)
  each (sub-)task selects — the same function-calling / tool-selection mechanism the chat agent
  already uses for `search_workflows` / `run_code` / `request_new_tool`. Keep `triggers` only as
  a cheap pre-filter / back-compat, never as the authority.
- **Open registry:** adding a capability = adding a skill file; no router edit. This is what
  dissolves "can you exhaust the types" — you never enumerate; you register and infer.
- **Catch-all is first-class:** when no skill matches above confidence → **synthesize** (new
  workflow via `request_new_tool`) or **ask**, never force the nearest match. This is the rule
  that would have stopped the empty dock/ADMET card.

## 3. Per-skill presentation contract (fixes the flat-card gap)

Every skill declares how its output renders, so presentation stops being thrown away by
`to_pipeline_card`:

- **Pattern skills** declare the card *shape*: `sequential-chain` → ordered steps with typed
  output→input handoffs; `fork-join` → branches visibly converging into the integration step
  (not a flat list named only after the sink); `fan-out-rank` → one input fanning to N analyses
  then a ranking step.
- **Operation skills** declare their *card type*: `generator-adaptation` → a **model-version
  card** (before/after metrics, fixed holdout, reviewer-gated promotion — BD doc §7.2), not a
  Nextflow pipeline card.

## 4. Flow (end to end)

```
request
  → pattern skill (infer shape) → decomposition structure (steps + edges) + card shape
  → per sub-task: operation skill (infer capability) → engine/route + card type
  → compose; no skill fits → synthesize or ask (never nearest-bucket)
  → render each (sub-)task via its skill's presentation contract
```

"Adapt the generative model to our chemical series" (BD doc §5.4 Adapt, verbatim) →
pattern skill = `single` (not a fork-join fan-out) → operation skill =
`generator-adaptation` → route Models/Adapt (ml_training generator branch) → **model-version
card**. Not dock+ADMET, not an empty pipeline card.

## 5. Migration (incremental, measurable — no big-bang rewrite)

1. **Author `generator-adaptation` as the first operation skill** (this doc's prototype:
   `backend/lib/galaxy/ai/skills/generator-adaptation.md`), with a `description` for inference
   selection and a presentation contract. It is the demo's exact failing case and a documented
   SYSUCC direction, so it's the right first peel-off.
2. **Give the decomposer the skill descriptions and let it infer**, delegating recognised
   operations to their skill instead of the monolith's drug-discovery template. Retire the
   `_TRAIN_VERBS` regex gate; selection becomes inference.
3. **Close the capability gap the skill names:** `ml_training` has generator-adaptation
   branches for single-cell diffusion, protein diffusion, and LLMs, but **no small-molecule
   generative (ReINVENT-style) branch** — that's why the documented small-molecule "adapt the
   generative model" direction has nothing real to route to. Build that branch so the skill
   yields a real model-version card.
4. **Peel each monolith capability section into its own operation skill** the same way
   (drug-discovery `:7026`, cryo-EM `:7051`, …), and each decomposition section into a pattern
   skill (`:7130` fork-join, `:7151` sequential) with its presentation contract.
5. **Measure offline each step** on the decomposition benchmark
   (`scripts/routing_eval/decomp_model_bench.ts` + `decomp_judge.py`, gold
   `evaluation/datasets/decomposition_real/`) via `DECOMP_ASSISTANT_MODULE` A/B, plus
   per-operation evals. No speculative deploys; each skill is a measurable unit.

## 6. Why this is the right target

- **Inference, not keywords** — skills picked by semantic match to `description`.
- **Open, extensible** — register a skill, no router change; uncovered → synthesize/ask.
- **Per-pattern presentation** — a first-class property of each skill, not discarded.
- **Grounded** — operation skills are the documented SYSUCC Models tracks / three kinds of
  learning, not an invented enum.
- **Testable** — each skill authored + evaluated independently, vs. one untestable mega-prompt.
- **Builds on what exists** — extends `SkillManager`/`SkillLoader`, doesn't fork a new system.

Prototype: `backend/lib/galaxy/ai/skills/generator-adaptation.md` (next).
