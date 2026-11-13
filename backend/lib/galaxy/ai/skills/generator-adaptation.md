---
name: generator-adaptation
title: Generator Adaptation (Models → Adapt)
description: >-
  Select this when the user wants to ADAPT or fine-tune an existing GENERATIVE model
  (molecule / peptide / protein generator) on their own data — "adapt the generative
  model to our chemical series", "fine-tune the molecule generator on our compounds",
  "continue-train the peptide designer on our actives". This is the documented hospital
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

**The executor already exists — route to the named workflow, do NOT nearest-retrieve.**
For a small-molecule (SMILES) generator, route to the catalog workflow **`reinvent4_finetune_rl`**
("Reinvent4 Finetune Rl") with `run_type=transfer_learning` (`stage=transfer`): it fine-tunes the
base REINVENT4 prior on the user's `train_smiles` series → a `*_finetuned.model` checkpoint. It
runs on the `reinvent4-nf` container (the CLI + baked-in priors). This is `workflow_generation`
with the **exact target** `reinvent4_finetune_rl` — NOT the nearest-catalog match (which misroutes
to dock/ADMET), and NOT `reinvent4_lead_design` (that only *samples* a frozen prior = inference).

- Inputs: `train_smiles` = the user's chemical series; `prior_path` optional (empty → container
  default prior); `epochs`, `stage` (transfer | rl | both).
- Modality note: small molecule → `reinvent4_finetune_rl`. Peptide/protein generator adaptation
  → the structure-diffusion path (`ml_training` `protein_diffusion`); single-cell → `scrna_diffusion`;
  LLM → `ludwig_llm`. **The gap here is ROUTING, not a missing executor** — the decomposer today
  sends "adapt the generative model" to an empty dock/ADMET fan-out instead of to
  `reinvent4_finetune_rl`.

## Presentation contract (model-version card — BD doc §7.2)

The run produces a new generator checkpoint (`*_finetuned.model`); present it as a
**model-version card**, not just a generic pipeline card:
- base prior + the adaptation SMILES series (identity validated);
- adaptation metrics (e.g. NLL / validity / novelty / series-similarity before vs after);
- the produced checkpoint path, as a new model version;
- **promotion gated on reviewer approval** — the adapted model is proposed, not auto-deployed.

(The `reinvent4_finetune_rl` after-run surfaces the checkpoint + training metrics; the
model-version framing is the presentation layer on top of that workflow's outputs.)

## Validation / honesty rules

- Keep measured vs predicted separate; report the holdout metric with a CI, not a point boast.
- Never claim an improvement without the fixed-holdout before/after.
- If the modality has no adaptation branch (small molecule today), state the gap and route to
  the nearest supported capability — do not present an unrelated or empty workflow card.

## Provenance

Documented capability: `internal project notes` §5.4 (Models →
Adapt), §7.2 (Model adaptation on hospital data → model-version card), §7.3 (generator
adaptation). Architecture: `docs/20261111_SKILLS_ARCHITECTURE_TASK_HANDLING.md`.
