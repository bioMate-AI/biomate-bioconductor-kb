# Routing training-data generation plan (generator + independent auditor)

Goal: build routing SFT data for the local instruct model (Qwen3.5-27B) to select the correct
workflow for a request. Measured on the **held-out RealBio cross_domain_routing (200)** — never
trained on, with a verified **no-overlap** guarantee.

## Data sources (multi-source; each overlap-checked vs RealBio)
1. **DB reverse-generation (primary, full coverage)** — the 300M+ tool/workflow DB covers the
   entire ~4,200-workflow label space (incl. drug-discovery/virtual-cell workflows no public
   repo reaches). Queries are **grounded in real artifacts** — `input_types`, `tools_used`,
   `params_schema`, `scientific_context`, `usage_guide`, `edam_operations` — describing the
   *data + goal* a user has, **never paraphrasing the workflow name/description** (avoids the
   circularity that invalidated the first attempt). Hard negatives / "disqualified" candidates
   come from the DB's **when-NOT-to-use** signal (`tool_compatibility` data-type mismatches,
   confusable same-domain workflows) and BioMate's own routing prompts ("Do NOT use" logic).
2. **Real GEO study-grounded** — 1,244 real NCBI GEO experiment descriptions → correct nf-core
   pipeline (sequencing assays). Real, non-circular. Overlap vs RealBio: max 0.24 (clean).
3. **Curated benchmark seeds** — protocol_to_workflow (35), lane_arbitration (40),
   workflow_generation (40): real human-curated, used as few-shot exemplars + extra training.
   Overlap vs RealBio: max 0.17/0.26/0.42 (clean).

## Generation method (survey-informed: APIGen-MT / Magpie / Evol-Instruct)
- **Ground, don't paraphrase** (APIGen-MT): generate the user request from the workflow's real
  I/O + tools + scientific_context, as a data/goal scenario.
- **Persona diversity** (PersonaHub): sample requester personas (clinician / core-facility /
  computational biologist / PI) and phrasing registers.
- **Difficulty control** (Evol-Instruct): vary from direct to indirect/underspecified; include
  confusable pairs (hard negatives).
- **Quality > quantity** (LIMA/Magpie): generate broad, then **filter hard** to the best.

## Generator + independent auditor (the two-role verification you asked for)
- **Generator** (LLM A): for a sampled DB workflow, emits `{query, correct_workflow, candidates,
  rationale}` grounded in that workflow's real artifacts + a persona.
- **Independent Auditor** (LLM B — a DIFFERENT model from the generator, to avoid self-bias):
  scores each item on: (a) **grounded & realistic** (reads like a real request, not a
  description paraphrase); (b) **unambiguous correct label** (the query genuinely routes to
  correct_workflow, not equally to a distractor); (c) **valid candidates** (correct present;
  distractors plausible; ≥1 hard negative); (d) **non-circular** (doesn't name/echo the
  workflow); (e) **no RealBio overlap**. Committee majority-vote + reason; only PASS items are
  admitted. (Mirrors APIGen-MT's format/policy/LLM-judge stack.)
- **Deterministic gates first** (cheap, before the auditor): schema check (correct in candidates),
  `overlap_check.py` (drop any near-duplicate to RealBio), exact/near dedup within training.

## Splits & leakage control
- Train/dev from generated + GEO + curated seeds. **RealBio-200 held out entirely.**
- `overlap_check.py` enforces no near-duplicate query (token+char-3gram Jaccard + substring)
  between ANY training item and RealBio. Current audit: all sources max ≤ 0.42 (no dup).
- Optional second fresh test: recent post-cutoff GEO/ENA studies.

## Evaluation
- Serve base + routing-LoRA via vLLM (one endpoint). 2×2 {base,SFT} × {starved, in-format}.
- Metric: top-1 select-from-candidates (correct or acceptable_alt), over ALL items, paired
  bootstrap 95% CIs. Report candidate-context effect vs true SFT lift. Save all raw outputs.

## Status
- Built: GEO real data (1,244), curated-seed audit, overlap checker, 2×2 eval harness,
  shared prompt, SFT formatter. Next: implement generator + auditor, run DB reverse-gen with
  auditing, then train→serve→eval on a GPU (spot).
