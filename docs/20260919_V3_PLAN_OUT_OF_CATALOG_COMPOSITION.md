# v3 plan — out-of-catalog capability via hierarchical compositional generation

**2026-09-19.** v3 goal: measure (and enable) BioMate's ability when **the required workflow does not
pre-exist** — by generating it **compositionally** from building blocks, hierarchically (phases → steps
→ blocks), not one-shot.

## Why v2 does not already cover this (verified)
- `rag_routing` guarantees the gold is in candidates; `routing` forces a name — **no abstention / no-match**.
- `wfgen` = intent → **category** (classification), not workflow synthesis.
- `interwf`/`chaining` **compose existing** workflows (assume they exist).
- `decompose` is **descriptive** — breaks an *existing* workflow into phases→steps from step metadata.

The missing piece is **compositional-generative** decomposition: synthesize a *new* pipeline from
blocks. Same hierarchical shape as v2 decompose, opposite direction (compose, not read).

## The three building-block granularities (user's framing)
| Granularity | Source | Local status |
|---|---|---|
| **tool functions** | tools DB (12,312; inputs 5,674 / outputs 5,119 / edam_operations 1,661) | ✅ have I/O |
| **submodule workflows** | nf-core subworkflows (`subworkflows/nf-core/*/main.nf`) | ⚠️ thin locally → **box fetch** |
| **workflows** | 4,200 | ✅ |

## Design
1. **Multi-granularity WKG** — extend `export_workflow_kg.py` to add tool-function and submodule nodes
   with I/O types, so blocks at any level can be **type-composed** (output type feeds next input type).
   Reuses the existing `precede`/type-flow machinery.
2. **Hierarchical generation task** (grounded, simplified by construction):
   - need → **biological phases** (e.g., QC → alignment → quantification → differential → enrichment),
   - → **steps within each phase**,
   - → **bind each step to a block** (tool function / submodule / workflow), validated by I/O-type flow.
   This decomposition-first approach avoids one-shot whole-workflow generation.
3. **Out-of-catalog trigger** (the abstention/fallback ladder, per CLAUDE.md indexed→generate→run_code):
   - no single workflow matches → **compose from blocks** (generate),
   - genuinely nothing fits → **abstain / clarify**,
   - ad-hoc/small → **run_code**.
4. **Contrastive**: block alternatives at each step = hard negatives (which block correctly realizes
   the step given the I/O types) — same contrastive principle as routing.

## Measurement (primary v3 deliverable) — workflow-removal / reconstruction eval
- Take real (query → workflow) pairs; **remove the true workflow** from the catalog/candidates.
- Score whether the model (a) recognizes no direct match, and (b) **reconstructs an equivalent
  phase→step→block plan** whose composed I/O types are valid and whose steps cover the removed
  workflow's function.
- Reuses the **family-holdout substrate** (169 workflows already held out) + the WKG for validity checks.
- Metrics: no-match detection rate; plan validity (type-flow valid); functional coverage vs the removed
  workflow's steps; over-generation (hallucinated blocks) rate.

## Baseline measured (2026-09-19) — reference bar
`eval_removal.py` on 80 removal cases (target workflow removed from candidates), model = gpt-5-mini:
- **composed_rate 1.00** (always builds a multi-step plan, never forces one workflow)
- **validity_rate 1.00** (named blocks real / available / ≠ removed target — no hallucination)
- **mean_step_coverage 0.54** (reconstructs ~54% of the removed workflow's true steps; buckets: 16 ≥0.8,
  33 @0.5–0.79, 22 <0.5, 9 @0)

Interpretation: composition/abstention comes naturally to a strong model; **reconstruction FIDELITY is
the gap** (~54%). v3's WKG-grounded compositional training targets coverage >0.54; the trained on-prem
model runs the same harness (`--url` vLLM) to measure it. Artifacts: `removal_eval.jsonl` (150 cases) +
`removal_eval_result.json` in S3 `.../eval/`.

## Measured v2 models (2026-09-20) — the gap is real
Removal eval on the trained v2-SFT models (direct-load, 80 cases), step-coverage (LLM-judge):
- **4B**: 0.30 · **27B**: 0.40 · gpt-5-mini baseline: 0.54.
- 27B > 4B (capacity helps; train loss 0.305 vs 0.517), both below frontier → **v3 compositional
  training is warranted**, with the 27B as the better base.
- CAVEAT: `composed_rate` is a brittle format metric (27B answers with a concise pick, not the exact
  JSON-list the regex counts → 0.05, despite 0.40 semantic coverage). **Trust `mean_step_coverage`
  (LLM-judge); relax/drop composed_rate** in the v3 eval.
Results: S3 `.../eval/removal_eval_{small,large}_trained.json`.

## Sequence
1. Extend WKG to multi-granularity (tool functions + submodules + workflows).  *(needs nf-core
   subworkflow fetch on the box for full submodule coverage.)*
2. Build the **removal/reconstruction eval** first → measure the gap honestly.
3. Add training only where the eval shows gaps: compositional generation, abstention/no-match,
   compose-when-missing.

## Explicitly deferred out of v2
v2 stays as-is (descriptive decompose + compose-existing). v3 adds compose-what-doesn't-exist. Keeping
versions separate per the version-by-version + anti-overfitting approach.
