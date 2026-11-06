# BioMate On-Prem LLM — Multi-Task Data & Joint Training Plan

Status: DRAFT, ready to execute once the routing 2×2 eval confirms real SFT lift.
Principle: **scale the coverage, gate the quality.** One jointly-trained multi-task LoRA over
the structured task cluster; knowledge stays in retrieval, skill goes in the weights.

Related: [TASK_CATALOG.md](TASK_CATALOG.md) (T01–T28), [ROUTING_DATAGEN_PLAN.md](ROUTING_DATAGEN_PLAN.md),
[SELF_EVOLVING_SURVEY.md](SELF_EVOLVING_SURVEY.md), [SMALL_DOMAIN_LLM_SURVEY.md](SMALL_DOMAIN_LLM_SURVEY.md).

---

## 1. Target artifact

A **single QLoRA adapter** on the natively-multimodal Qwen base, trained jointly on the P0/P1
**structured** task cluster, served as one endpoint. NOT five swappable per-task adapters
(deployment) and NOT sequential per-task fine-tunes on one adapter (interference/forgetting).

Rationale (from the self-evolving survey + small-domain-LLM survey):
- Domain *knowledge* doesn't need to be trained — it's supplied in-context (retrieval beats
  parametric domain FT for grounded tasks). We train the transferable **skill** of operating
  over retrieved context.
- Related structured tasks share reasoning → positive transfer, better data efficiency.

---

## 2. Task roster for the first joint model

Only **structured, verifiable, high-frequency** tasks in round 1. Vision + long-form generative
tasks are separate later tracks.

| Task | Catalog | Type | Verifier (the quality gate) | Grounding source |
|---|---|---|---|---|
| Intent classification | T01 | classify | independent auditor + label-membership | galaxy-assistant intent map + real queries |
| Domain inference / clarification | T03 | classify/gen | auditor + label whitelist | workflow domain + query |
| Workflow routing | T05 | select | **schema: correct∈candidates**, auditor, overlap | 4,200-workflow DB + GEO |
| Schema-grounded param resolution | T06 | slot-fill | **execution: values valid vs params_schema** | params_schema (3,058 wf) + rule-pass output |
| Workflow-mod classification | T10 | parse | **schema: step_index/keys valid** | current workflow + edit utterance |
| Log diagnosis / root-cause | T18 | classify | category-membership + auditor | real `real_exec_err` logs |
| Autofix / QC remediation | T19 | plan | **execution: does the re-run pass?** | real failures + param schema |
| Output interpretation | T20 | interpret | **exact-value match vs source file** | parsed output tables/metrics |

Deferred to later rounds: T17 figure interpretation (vision track), T14/T21 evidence synthesis &
report prose (distillation + citation grounding), T22/T23 regulatory (out of scope).

Kept deterministic (never trained): param rule-pass, schema validation, graph search, output
parsing, auth — see TASK_CATALOG "Work BioMate does without an LLM".

---

## 3. Per-task data generation — one recipe, per-task grounding

Reuse the routing machinery (`generate_routing_data.py` → `audit_*` → `overlap_check.py`), specialized per task:

1. **Ground in real artifacts** (never paraphrase the target's own description — anti-circularity).
   Each task pulls from the DB/logs column named above.
2. **Persona + difficulty variation** (Evol-Instruct-style) for diversity; include *negatives*
   (queries that should map to nothing / no param / "ask clarification") to teach restraint.
3. **Deterministic gate first** (cheap, high-precision): schema membership, value-legality,
   category membership, name-leak guard, overlap vs held-out test.
4. **Independent auditor second** (different model than generator): realistic + correct-label +
   non-circular. For execution-verifiable tasks, prefer the execution/schema check over the LLM judge.
5. **Shared prompt template per task** (like `routing_prompt.py`) imported by BOTH the SFT
   formatter and the eval → train == eval protocol, byte-identical.

Volume target: **broad + verified, not raw scale.** ~1–3k *type-diverse, balanced* examples per
task (LIMA/Magpie lesson: quality ≫ quantity). Over-generate 2–4×, filter hard.

---

## 4. Mixture & joint training

- **Task-balanced mixture**, proportioned by importance and difficulty — NOT raw counts (else
  routing/transcriptomics drowns the rest). Start ~equal per task, adjust from per-task dev loss.
- **Domain balance within routing/param** to counter the transcriptomics skew (1,695/4,200).
- Format: `{system, user, assistant}`, **assistant-token-only loss** (`SFTConfig(assistant_only_loss=True)`).
- QLoRA r=16 (raise to 32 if underfitting), all proj modules, 4-bit NF4, `paged_adamw_8bit`,
  cosine, ~2–3 epochs over the pooled set. One adapter, `train_qlora_pilot.py` (already proven).
- Checkpoint → S3 each save (spot-reclaim safety; NVMe is ephemeral).

---

## 5. Evaluation — per-task, not aggregate

Aggregate accuracy hides interference (joint training can lift some tasks, hurt others).

- **Per-task held-out sets** + the RealBio suite; report each task separately.
- Map to **LifeSciBench axes** (evidence handling / analysis / validation-ops / …) as the north-star.
- **2×2 design** where a context confound exists (as in routing: {base,sft}×{starved,in-format}),
  paired bootstrap CIs, raw outputs logged.
- **Baselines** (small-domain-LLM survey): Aloe-Qwen2.5-7B, OpenBioLLM-8B, Meditron — head-to-head
  on the same held-outs.
- **Collapse/diversity guard:** track output entropy / unique-answer rate across self-evolving rounds.
- **No-leak invariant:** every training source passes `overlap_check.py` vs every held-out (<0.5 sim).

---

## 6. Sequencing (gated on evidence)

- **Phase 0 (now):** prove the loop on routing (verifiable). 2×2 eval = go/no-go. **Do not build
  the multi-task set until SFT lift is confirmed with clean CIs.**
- **Phase 1:** build grounded, verifier-gated data for the rest of the structured cluster (§2),
  each with its shared prompt template.
- **Phase 2:** one joint multi-task training run (§4) → per-task eval (§5). Iterate mixture.
- **Phase 3:** add output-interpretation grounded prose, then vision (T17) and evidence/report tasks.

---

## 7. Self-evolving flywheel (how it keeps improving)

Once the joint model is live (STaR/ReST-EM loop, grounded verifier — see SELF_EVOLVING_SURVEY):
`production turn → log (intent, route, params, run outcome, user correction) → mine
(successes = positives; failures + corrections = hard negatives + Reflexion memory) → verify
(execution/schema + independent auditor, GROUNDED not self-judged) → ReST-EM retrain on passers,
few iterations, real data mixed in → DSPy/TextGrad prompt-optimize between rounds → guard
(diversity monitor, held-out RealBio, overlap-check each round)`.

V-STaR upgrade: keep the auditor-*failed* generations to train the verifier (don't discard them).

---

## 8. Vision track (T17), parallel

Same base (vision tower already staged: 333 vision tensors + processor). Serve full multimodal
model + this LoRA (LoRA touches text layers only). Data: render figures from data we already have
(DE tables → volcano, QC metrics → plots) so the gold interpretation is **computable/verifiable**,
plus PMC open-access figures+captions. Benchmark base vision first; fine-tune only the gaps.

---

## ADDENDUM — Intent decomposition (T01/T09) is a first-class task (was missing)

**Gap:** the task cluster above trained the *second* level (given a query → one workflow/param/etc.)
but omitted the *first* level — **decomposing a multi-intent request into ordered sub-tasks**. Real
BioMate queries are often multi-step ("align RNA-seq → DE → pathway enrichment") or parallel ("ADMET
+ literature"). Catalog refs: **T01** (multi-intent analysis/decomposition, `galaxy-assistant.ts`
intent analyzer + `intent_parser.py`/`task_decomposer.py`) and **T09** (chain composition,
`chain_composer.py`, `chain_planner.py`).

**Add as a task:**
- Output: `[{sub_task, intent, order, depends_on}]` (a small DAG).
- Grounding: existing `chain_composer` retrieved chain patterns + real multi-step DB workflows +
  **multi-step protocols/GTN tutorials** (a protocol IS a gold decomposition) — see the domain-text survey.
- Verifier (grounded): each sub-task routes to a valid workflow (routing verifier); DAG acyclic with
  satisfiable I/O deps (`chain_planner` compatibility); coverage of every requested step (T09 coverage).
- Eval: decomposition F1 + ordering/dependency correctness + end-to-end chain runnability.
- Train: include in the joint multi-task mix (shares reasoning with routing).

This is a first-stage prerequisite to routing/param and belongs at the front of the pipeline; it is
also a natural target for inner-loop skill evolution (decompose-multi-omics skill).
