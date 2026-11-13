# Models module — own-compute + OSS-reference direction (2026-11-12)

Founder direction (this session), in their words:
- "isn't there any open source platform of ml/dl we can leverage directly? even galaxy
  has its interface and functions — at least take a reference of them, instead of building
  from scratch."
- "why are there still NVIDIA-hosted models?"
- "the interactive panel never succeeded in biomate."
- "Galaxy Interactive Tools (Jupyter) as the general path — not good for clinic people
  without UI."
- "you can have two paths, a single one is not good."

## Principles

1. **Leverage OSS, don't build trainers from scratch.** We already compose: **Ludwig**
   (149 refs — declarative, data-type-driven over tabular/text/image/sequence, native LLM
   fine-tuning + AutoML/hyperopt), **MLflow** (registry + tracking), **BentoML** (serving),
   Chemprop / TRL / transformers / scikit-learn. Ludwig is effectively the general ML/DL
   engine; the Models UI should be a thin no-code front over it (and reference AutoGluon /
   AutoML for "point at a table → train" simplicity), not a hand-maintained per-type form
   taxonomy (`PanelModelType` / `SPEC_FIELDS`). We are a **Galaxy** fork — reference its
   tool-form UI and tool framework too.

2. **Run on our OWN compute, not NVIDIA.** Pretrained inference should run OSS weights on
   our own Galaxy/AWS Batch (the Boltz-2 pattern), not NVIDIA's hosted BioNeMo API (which is
   an external, unreliable dependency — Evo2/OpenFold2 500s, AlphaFold2/ESMFold 410-EOL).

3. **Two paths, not one** (different audiences):
   - **No-code UI path — clinical users.** The UI-driven training launcher over Ludwig /
     AutoML: choose data → role columns (dropdowns) → train, with gates + provenance. A
     code notebook is wrong for non-coder clinicians.
   - **Code path — power users.** Arbitrary ML/DL in code via the owned **`run_code`
     sandbox** (`POST /api/code/run`, `biomate-runcode` image). Galaxy Interactive Tools
     (Jupyter) **never worked in BioMate** and are not the product path for clinicians or
     power users on this surface (IT may still exist for diagnostics elsewhere).

## Shipped this direction

- **Hide NVIDIA-hosted models until owned** (`models_inference._bionemo_catalog`): advertise
  only models BioMate runs on its own compute — an owned AWS Batch path (`origin_override=
  'aws_batch'`, Boltz-2) or a configured self-host NIM. Pure NVIDIA-hosted (Evo2, OpenFold2)
  are filtered out; the genomic "Run a model" domain default is cleared so it honestly shows
  "no model for this domain" instead of resurfacing a hidden NVIDIA model.
- Boltz-2 reads "BioMate compute" (Round C).
- **Two paths on Train tab** (2026-11-12): No-code (default `TrainingLauncher`) ↔ Code
  (`CodeSandboxPath` → `POST /api/code/run`). Project files stage from S3 when `project_id`
  is passed (same ownership + 100 MB cap as the chat tool path).

## Follow-ups (tracked)

1. **Own Evo2 / OpenFold2 execution** — both are open-source weights; give them a Batch
   path like `boltz_structure_prediction`, then re-enable with `origin_override='aws_batch'`.
   Evo2-7B / OpenFold2 are the tractable ones; Evo2-40B needs large-GPU sizing.
2. **Ground the training UI on Ludwig's schema** (+ an AutoML "just train" mode) rather than
   hand-maintained `SPEC_FIELDS`; keep it no-code.
3. **Interactive Tools diagnosis (optional)** — understand why Galaxy IT never succeeded in
   BioMate; do not block the Models code path on fixing it.
