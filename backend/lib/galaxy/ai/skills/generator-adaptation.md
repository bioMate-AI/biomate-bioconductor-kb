---
name: generator-adaptation
title: Generator Adaptation (Models → Adapt)
description: >-
  Select this when the user wants to ADAPT or fine-tune an existing GENERATIVE model
  (molecule / peptide / protein generator) on their own data — "adapt the generative
  model to our chemical series", "fine-tune the molecule generator on our compounds",
  "continue-train the peptide designer on our actives". This is the documented SYSUCC
  "Models → Adapt" capability and the "generator adaptation" kind of learning. It is NOT
  docking, ADMET, virtual screening, or de-novo generation from scratch; it is NOT a
  property-PREDICTOR retrain (that is predictor-retraining); it is NOT merely running an
  existing model (that is inference). The outcome is a new generator checkpoint, presented
  as a model-version card — never a Nextflow dock/ADMET pipeline.
triggers: [adapt the generative model, fine-tune the generator, adapt generator, continue-train the generator, fine-tune the molecule generator, adapt the molecule model, fine-tune the peptide generator]
domains: [drug_discovery, structural_biology]
version: 1.0
---

## When this skill applies (inference, not keywords)

Apply when the task MEANS "take an existing *generative* model and update its weights on the
user's data." Distinguish the three kinds of learning (BD doc §7.3) — they route differently:

| The task means… | Skill | Output |
|---|---|---|
| update a GENERATOR's weights on our data | **generator-adaptation** (this) | new generator checkpoint → model-version card |
| retrain a PROPERTY/potency PREDICTOR on our assays | predictor-retraining | new predictor version → model-version card |
| just RUN an existing model to get predictions | (inference — ordinary prediction route) | a results table |
| capture SOPs/corrections as rules | knowledge-adaptation | a knowledge base, *not* model training |

Negative guards (do NOT select this skill):
- "dock / screen / predict ADMET / hERG / binding" → docking / ADMET operation skills.
- "design / generate N candidates from scratch" with no adaptation on user data → de-novo
  generation (e.g. `reinvent4_lead_design`), not adaptation.
- A request with no user data to adapt ON → ask for the adaptation data, don't fabricate a run.

## Decomposition shape

A bare "adapt the generative model to our chemical series" is a **single** task (pattern skill
= `single`), NOT a fork-join fan-out. Do not decompose it into dock + ADMET + integrate — that
mistranslation is the known failure (`galaxy-assistant.ts:7039,7148`). It only becomes
multi-step if the user explicitly chains it ("adapt the generator, THEN screen the outputs").

## How to handle (route)

Route to the Models / `ml_training` **generator-adaptation** path, not catalog workflow search:
- modality from the data/target: small molecule (SMILES series) · peptide · protein.
- mode = **adapt / continue-train** from a base checkpoint (not train-from-scratch), on the
  user's authorized data; fixed holdout; before/after vs the previous version.
- Backend: `ml_training` has generator-adaptation branches for single-cell diffusion
  (`scrna_diffusion`), protein/peptide structure diffusion (`protein_diffusion`), and LLMs
  (`ludwig_llm`). **Capability gap:** there is NO small-molecule generative (ReINVENT-style)
  adaptation branch yet — so a SMILES-series request currently has nothing real to route to.
  Until that branch exists: say so honestly and offer the supported path (predictor-retraining
  on the same assays, or de-novo generation), rather than emitting a wrong/empty card.

## Presentation contract (model-version card — BD doc §7.2)

Render the result as a **model-version card**, not a pipeline card:
- base model + the adaptation dataset (identity + units validated);
- **before / after** metrics on a **fixed holdout** (same split as the previous version);
- a diff vs the previous checkpoint;
- **promotion gated on reviewer approval** — the adapted model is proposed, not auto-deployed.

## Validation / honesty rules

- Keep measured vs predicted separate; report the holdout metric with a CI, not a point boast.
- Never claim an improvement without the fixed-holdout before/after.
- If the modality has no adaptation branch (small molecule today), state the gap and route to
  the nearest supported capability — do not present an unrelated or empty workflow card.

## Provenance

Documented capability: `docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_EN.md` §5.4 (Models →
Adapt), §7.2 (Model adaptation on hospital data → model-version card), §7.3 (generator
adaptation). Architecture: `docs/20261111_SKILLS_ARCHITECTURE_TASK_HANDLING.md`.
