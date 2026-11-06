# Two-LLM Architecture + Retrieval-as-Double-Check

**Date:** 2026-10-01
**User direction:** (1) two LLMs — a **base** and a **domain-professional (trained)** model; (2) even
with trained knowledge, **the DB/knowledge must still be searched to double-check**.
Builds on [[20261001_TASK_FLOWS_DB_SUPPORT]], [[20261001_DOMAIN_BACKGROUND_CPT_PLAN]],
[[20261001_LLM_HARNESS_TASK_SPLIT]].

## The two models
| Model | What it is | Handles |
|-------|-----------|---------|
| **Base LLM** | general reasoning / instruction-following (fast, cheap) | orchestration + the **harness-carried 🟢 tasks** (routing pick, param-fill-with-rules, phrasing, dataset-prereq, tool-rec) — where the model is *invariant* (routing is 0.94 even on an untrained 4B) |
| **Domain-pro LLM** | **CPT on the background corpus (DB enrichment + PMC + GTN) + SFT on domain judgment** | the **🔴 domain-judgment tasks**: findings_interpretation, model_selection reasoning, out_of_catalog_composition, workflow_generation, scientific_qa, and the domain slice of intent-interpretation (task_decomposition / clarification) |

**The router between them is the task-split we already built** ([[20261001_TASK_FLOWS_DB_SUPPORT]]):
🟢/general → base; 🔴/domain-knowledge → domain-pro. On-prem, both run in the customer VPC.

## Retrieval is STILL on — as the double-check (the key safeguard)
Training background knowledge into the domain-pro does **not** remove retrieval. The two play
distinct roles:
- **Trained background knowledge = a reasoning PRIOR.** It lets the domain-pro reason fluently about
  mechanisms/methodology/when-and-why — the judgment the harness can't supply.
- **Retrieval (DB + knowledge) = the GROUND-TRUTH CHECK.** The harness still searches the DB/knowledge
  for every domain call and **double-checks** the model's output against it, because parametric
  knowledge goes **stale** (the DB moved 2,455 → 4,200 workflows) and can hallucinate.

So the domain-pro operates **open-book with verification**: retrieve relevant DB/knowledge → reason
with the background prior → **ground/verify the answer against the retrieved evidence** (cite-or-abstain;
`grounded_pick`; the VerificationLayer). **Facts always come from retrieval**; the trained knowledge
makes the model a better *reasoner over* and *judge of* that retrieved evidence, not a replacement for it.

```
request ─▶ harness router (task-split)
            ├─ 🟢 general/structural ─▶ BASE ─▶ [retrieval grounds output]
            └─ 🔴 domain-judgment ───▶ DOMAIN-PRO ─▶ [retrieval DOUBLE-CHECKS output]
                                         ▲ background prior (weights)
                                         └ DB/knowledge retrieved into context + verified against
```

## Consequences
- **Background CPT targets the DOMAIN-PRO** (not "the one LLM"). The corpus work (DB enrichment +
  PMC volume + GTN) feeds it. Base stays general (maybe light tool-use/orchestration SFT).
- **Size comparison = the domain-pro**: 9B (Insilico winner) vs 27B (ceiling). Base can be smaller/faster.
- **Eval in the REAL mode only — open-book with retrieval.** The model always runs with both the
  background prior AND retrieval, so that is the mode to measure. Closed-book tests a mode it never
  runs in (the same error as the closed-book mid500 F1 that misled us). The decisive comparison is
  **base vs domain-pro, BOTH open-book**, on the 🔴 tasks: if domain-pro ≈ base open-book, CPT added
  nothing (retrieval carried it) and isn't worth it; if domain-pro > base open-book, the background
  earned its place. Metric = execution grading (runnable tasks) + knowledge MCQA (background), always
  with retrieval in context.
- **Why this is coherent with everything prior:** facts → retrieval (unchanged); background → weights
  for reasoning (the new layer); retrieval verifies the reasoning (the safeguard). No contradiction.
