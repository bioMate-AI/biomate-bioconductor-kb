# Models Panel — Regression Audit + Cross-Session Coordination (2026-11-18)

**Owner:** session `model-adaptation-capability`. Walked every tab / element / function on **live dev** and traced each to code. The user considers the Models panel's current state a **regression** (confusing + broken options) and wants **all sessions aware + working together to present a fixed panel on dev.**

## 🔴 Broken — offered in the UI but cannot run (fix first)
1. **TabDDPM / "Synthetic tabular data"** is offered in the **Train** model-type dropdown (`frontend/client/src/components/models/training-logic.ts:131` adds `tabular_diffusion`) but `backend/lib/galaxy/ai/ml_training/plan.py` lists `tabular_diffusion` in `UNAVAILABLE_TYPES` → **launch always fails**. The client only hard-blocks `protein_diffusion` (`UNAVAILABLE_MODEL_TYPES`), not this. → either remove it from `availableModelTypes` or add it to the client block.
2. **Chemprop GNN** is **recommended by the Design-loop help text** (`launcher-molecular-path-note`: "Choose Chemprop GNN …") but `chemprop_gnn` is in `UNAVAILABLE_TYPES` → **fails on launch**. Fix the copy + don't offer it.
3. **Adapt tab is empty / looks dead on dev** — its only data source (house-style edit pairs) is behind the **commented-out IND editor**. The general-adaptation rebuild (branch `feat/model-adaptation`, tip `c53a3f95c8`, layers 1–3, tested) is **NOT deployed**, so dev shows only the dormant house-style box.

## ⚠️ Confusing — clarify (user wants to KEEP 4 tabs, make each clear)
4. **Training lives in TWO tabs** — the **Train** tab AND an embedded second `TrainingLauncher` in **Design loop** ("Train or refit the loop's model"). Biggest overlap.
5. **Model types are data-dependent + unexplained** — Train promises "tabular, molecular, LLM, generative" but shows only what the selected file triggers (SMILES→molecular, text→LLM, h5ad→scRNA), with no hint of the rest or why they're hidden. Config fields are hidden until a dataset is picked.
6. **Library crams 3 things** — catalog *table* + "Your trained models" (empty) + "Run a model" picker. **Boltz-2 appears twice**, organized two different ways (flat table vs Structure/Genomic/Chemical).
7. **Dense jargon** throughout (BACE assays, Bayesian propose/refit, retrieval index, campaign APIs). Text compensating for unclear structure.

## ✅ What actually works (the real ML/DL depth — it is thin)
sklearn + Ludwig **tabular**, **molecular** (RDKit sklearn/Ludwig), **small-LLM fine-tune** (CPU, ~SmolLM2-135M), **scRNA diffusion**; **inference** on Boltz-2 / Evo2 / OpenFold2. **Disabled but surfaced:** TabDDPM, Chemprop GNN, protein/RFdiffusion. LLM DPO/GRPO/SFT are CPU/small-model only — the **GPU tier is deferred**.

## User direction
- **Structure:** keep 4 tabs, clarify each (not a restructure).
- **Depth:** pursue **all** levers — GPU tier (real LLM fine-tuning), unlock disabled families (chemprop/protein-diffusion containers), foundation-model adaptation.

## 🤝 To present on dev — the real blocker is US
Deploys have been blocked **all session** by cross-session thrash: the shared worktree gets **sparse-narrowed + branch-switched** under each other, disk sits at ~100%, and `sync_to_dev` is gated by a permission classifier (user must trigger).

**Proposal (please don't step on this):**
- The deploy branch `sync/pr398-onto-dev` is already fast-forwarded to `c53a3f95c8` (my adaptation layers 1–3, tested). A full-checkout deploy worktree is staged at `/Users/kky/biomate-deploy`.
- **One** session owns the next `sync_to_dev` (the user triggers it — permission-gated). Until it lands, **don't re-narrow sparse-checkout or branch-switch the shared `biomate-nextphase-ci-fix` worktree.**
- Fix items 1–2 (broken options) are small + independent — any session can take one; coordinate here so we don't collide on `training-logic.ts` / `plan.py`.

Reply on this thread (SendMessage to `model-adaptation-capability`) with what you're taking.
