# Root-cause: what is wrong in the whole on-prem LLM process (2026-09-28)

Evidence-based teardown of why scores looked like a "fail" and why mid-training hurts. Every number here
is measured this session.

## The measured facts
- Objective gold routing (candidate-grounded, no judge), matched 150-step SFT:
  **plain-base+SFT = 0.849** accept, **midtrain-1200+SFT = 0.796** → **mid-train lift = −0.053** (hurts).
- Fidelity scorecard macro = 0.458 — but that metric is **doubly invalid** (below).
- Data grounding: **routing gold that names a REAL catalog workflow = 72% (train), 62% (eval)** →
  **28% of train and 38% of eval routing examples have a HALLUCINATED gold workflow.**
- Knowledge-NLL during mid-train dropped ~1% (300→900) — it *did* learn the domain text — yet routing got worse.

## What is wrong — 5 coupled defects

### D1. Data generation is not grounded/validated → hallucinated names
`build_interactions_v3.py` pulls real DB anchors and *tells* Gemini "grounded in facts, never invent
names/params" — but there is **no validation step**. "Never invent" is an instruction, not enforcement;
nothing checks the generated workflow/tool/param names against `galaxy_ai_tools.db` and drops/repairs the
bad ones. Result: **28% of routing training targets name a fabricated workflow** (`clustermix` for
`clustall`, `Temporal Monitoring`, `Rdumi`…). The model faithfully learned to **confabulate plausible
names** — exactly what the diagnostic caught. BioMate's real catalog was available but not *enforced*.

### D2. The evaluation was doubly invalid
- **Fake gold:** `corpus_eval_big` was built by the same ungrounded generator → **38% of its routing gold is
  hallucinated**. You cannot measure correctness against fabricated answers.
- **Broken judge:** the fidelity metric is an LLM "coverage of the teacher answer" judge — proven unreliable
  (scored hallucinated `clustermix`=1.0; near-identical answers 0.0 vs 0.8).
- **Ungrounded prompt:** it asks routing/tool-rec with **no candidates**, so it tests the 4B's *memorization
  of 4,000 names* — not the retrieval-grounded product. → the 0.458 is meaningless. The one **curated,
  grounded** eval (`gold_routing_eval`, RealBio/dbtest) gives the trustworthy 0.849.

### D3. Task definitions are weak (no per-task contract)
One generic "generate 3 diverse interactions" prompt for all tasks; task type "emerges" from a menu; no
per-task output schema or validator. → mislabeled/mis-scoped tasks (committee: `parameter_extraction` is
doc-QA not slot-fill; `lane_arbitration`/`model_selection` are 5-way picks judged by prose-coverage → 0.17).

### D4. Why MID-TRAIN HURTS (the core conceptual error)
Mid-training injects **parametric knowledge**, but the agent's flagship skills (routing, param, decomposition)
are **catalog-grounded skills**, not general-knowledge recall. Routing = "map request → a *real workflow
name*," which needs the **catalog (retrieval)**, not PubMed facts. So mid-training:
1. **Adds knowledge the skill tasks don't use**, while
2. **shifting the base's distribution** toward the mid-train corpus. The domain mix was **~21% verbalized KG
   triples** (`"A (gene) interacts with B."` ×3 over 8.1M edges) — **degenerate, low-entropy text**. Continued
   pretraining on that pulls the base toward flat triple-patterns and **erodes the general/instruction
   ability** that SFT then can't fully recover (classic continued-pretraining forgetting; LoRA softens but
   doesn't remove it).
3. Net: knowledge-NLL drops (it memorized the flat text) **but downstream routing drops −5.3 pts**. Lower
   perplexity on domain text ≠ better agent — it traded skill for repetitive-text fit.
This is consistent with the earlier literature-less "wash" and the marginal NLL gain.

### D5. The unifying error
The process optimized **parametric knowledge** (mid-train) and **LLM-invented "diversity"** (ungrounded
generation) — the two things that DON'T determine agent quality — while under-investing in the two that DO:
**(a) clean, catalog-grounded, well-defined task data with real gold, and (b) retrieval-grounding at
inference.** The proof: the grounded, candidate-given routing eval already hits **0.849** with 150 SFT steps;
the ungrounded data/eval/mid-train are what produced the "errors."

## Fix direction (what to actually do)
1. **Ground-and-validate generation:** generate FROM the DB and **validate every name/param against it —
   drop or repair anything not in the catalog.** Zero fabricated targets. (One shared validator, not scattered.)
2. **Per-task contracts + objective graders** (RealBio `score.py` / Latch `eval_graders`): each task has an
   output schema + a programmatic validator; retire the LLM-coverage judge. Rebuild the eval from **curated
   gold**, not the generator.
3. **Knowledge via RAG, not mid-train:** for a 4B, serve literature/KG at inference (retrieval) + KG→SFT
   *reasoning* tasks. **27B = SFT-only** (do not spend mid-train compute).
4. **Eval in deployment mode:** retrieval-grounded candidates + per-task {mode, tokens}.

## Bottom line
Not a model fail — a **pipeline** fail in data-grounding + evaluation + a mis-applied mid-train. The 4B is
already strong (0.849 routing, grounded). Fixing D1–D3 (grounded data + objective eval) and dropping D4
(mid-train) is the path.
