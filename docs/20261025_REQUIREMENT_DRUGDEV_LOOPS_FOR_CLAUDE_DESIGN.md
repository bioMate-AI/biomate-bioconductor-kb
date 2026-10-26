# Requirements — Drug-Development LOOPS (for Claude Design)

**Date:** 2026-10-25. **For:** Claude Design (loop demo/walkthrough) + engineering.
**Why this doc:** prior framing muddled the loops (called them "small-molecule only" and
conflated them with the generic `t2` tutorial). This is the accurate, grounded spec.
Sources: the loop audit (`backend/experiments/autoloop_bridge.py`,
`qc_trace_monitor.py`, `drug_discovery/{api_router,auto_retrain,bayesian_optimizer}.py`),
the peptide map (`research/guangzhou_all_atom/`, `/Users/kky/sdl-macrocycle`),
`docs/20261002_BIOMATE_LOOP_INFOFLOW_READINESS.md`, `docs/20261004_committee/drugdev-readiness-map.md`.

> **Rule #1 — there are TWO distinct loops. Never conflate them, and never claim either is
> more autonomous than it is.** Modality is **both small molecule AND peptide (incl. cyclic)**
> — peptides are first-class, not a footnote.

---

## Loop A — Intra-run QC-gate remediation ("auto-loop")

A quality gate fires **within a single run** (ADMET / docking / PK) and proposes tightened
parameters. **Advisory, not autonomous.**

**Flow to depict:** run executes → a QC gate evaluates a metric against a codified
threshold → one of:
- **PROCEED (pass):** `autoloop_phase_complete` → the phase continues/completes.
- **RETRY (gate HALT → remediate):** the gate names the failing metric, shows a **was→now
  parameter diff** (e.g. real ADMET run `d0ff684b`: DILI high > 0.5 → `logp_max 5.0→4.0`,
  `mw_max 500→400`), and **the user chooses to start a new run** with those params.
  **BioMate does NOT auto-restart.** Regulatory halts (REGULATORY basis) emit a required
  action with **no** param tuning; only RISK_STRATIFICATION halts are tunable.
- **PIVOT (switch workflow on repeated failure):** **deferred / not built** — mark as roadmap
  if shown at all, never as a live feature.

**Honest status:** gate-fire is live and real-run-proven (`d0ff684b` hERG `0.012µM<1` halt,
DILI high); remediation is **advisory** (served via `/autoloop-suggestions`, the re-run is a
deliberate user action). Suggestions are deterministic (`param_tuner.remediate`).
**UI already exists:** `frontend/client/src/components/auto-loop-panel.tsx` — gate table +
per-gate remediation cards with the was→now diff + rationale/citation; `pass|escalated` banner.

**Must-nots:** no "self-optimizes / auto-reruns without the user"; no fabricated pause on a
clean run (safe control `46953d98` shows `qc_gates: []`).

---

## Loop B — Cross-round DBTL campaign loop (design → make → test → analyze)

A **persistent campaign object** iterates across rounds; wet-lab results feed back and refit a
surrogate that proposes the next round. This is the real "continuous loop = campaign."

### B1 — Small-molecule campaign (product-native today)
- **Campaign object:** `drug_discovery/api_router.py` `campaigns` table (per-campaign SQLite)
  + `auto_proposals` rounds (`round_number`, `proposed_smiles`, `scores`, `confidence_intervals`,
  `ad_statuses`, `triggered_by`). `POST /api/drug-discovery/campaigns`; wizard
  `drug-discovery-campaign-wizard.tsx`.
- **The loop engine:** `auto_retrain.py` polls the audit log for `INGEST_ASSAY` events → refits
  a **Bayesian-GP surrogate** (`bayesian_optimizer.py`, EHVI/Pareto) → re-scores the cached
  virtual library → writes round N+1 → optional CRO order (`cro_order_export.py`).
- **Lineage:** `round_number` accumulation + `wetlab_report_ingester.py` tags every field
  **measured-wetlab vs predicted-computational** (reference / species / study-type / confidence).
- **Status:** complete + platform-native for **small molecules (SMILES)**. The one partial link
  is close-back to the *generator* (the GP *surrogate* refits each round; a *generative*-policy
  retrain is a capability — see B2 — not yet a demonstrated live round-to-round product loop).

### B2 — Peptide / cyclic-peptide DBTL loop (the differentiated program)
Peptides are first-class. The loop (research program `research/guangzhou_all_atom/` +
self-driving lab `/Users/kky/sdl-macrocycle`):
- **DESIGN (own, trained-from-scratch generative diffusion — the moat):** PepGLAD latent-diffusion
  ladder trained from scratch (`m1_train_ae` → `m2_train_ldm` → `m2c_train_ldm` target-conditioned
  co-design; CycPeptMPDB + display-NGS data); UniMoMo cyclic fine-tune; the cyclic-LLM
  ("invert the data dependency"). **This is why the design engine is not "just AF3."**
- **STRUCTURE:** `Cyclic Peptide Cofold` (**Boltz-2**, `cyclic:true`, one Batch task/peptide;
  AF3 is a top-5 cross-check, not the at-scale engine — Boltz-2 is MIT-licensed, local, and
  predicts affinity).
- **BINDING (physics verify):** `Peptide Mmgbsa` / `Amber Peptide Mmgbsa` (MM-GBSA) and
  **`gromacs_pmx_fep`** (the peptide / cyclic / metal-bridged FEP engine; audited AWS-Batch GPU).
- **PROPERTY GATE:** Landry-grounded **availability predictor** (informational) + PAMPA/permeability
  + stability; the A3 fail-open gate (`peptide_gate.py`).
- **MAKE:** the **self-driving lab** (`sdl-macrocycle`) — **hybrid; never automate synthesis**
  (batch 48–96 to GenScript/WuXi); assays PAMPA / FP binding / plasma stability.
- **LEARN (close the loop):** **Diffusion-DPO** close-back (`dpo_peptide_trainer.py`,
  `dpo_unimomo_adapter.py`) — measured results become preference pairs that **retrain the
  generator**. This is the real round-to-round generator close-back.
- **Grounding programs:** αvβ6 (PDAC) + GRPR cyclic peptides, PD-L1 blockade (`pdl1_m2c_*`),
  multi-target pairs; ACT accelerator, SYSUCC / Soochow collaborations.
- **Honest status:** design + structure + binding + gate + SDL software + Diffusion-DPO close-back
  are **built**; strong **within-target**; **cross-target transfer is the open research front**.

---

## What the loop demo/walkthrough must cover

1. **Both loops, separated.** Loop A (intra-run QC remediation, advisory) and Loop B
   (cross-round DBTL), clearly distinct.
2. **Both modalities.** Small-molecule campaign AND the peptide/cyclic DBTL loop — peptides as a
   lead case, not an afterthought.
3. **The DBTL cycle explicit:** Design (generative, incl. our trained-from-scratch diffusion) →
   Make (SDL, human synthesis) → Test (assays) → Analyze (refit surrogate / Diffusion-DPO) →
   next round, with lineage across rounds and measured-vs-predicted provenance.
4. **Honest autonomy:** Loop A remediation is user-confirmed; Loop B make-step is human synthesis
   (never automated). No claim of a fully autonomous self-driving pipeline.
5. **Honest maturity badges:** product-native (small-molecule campaign, QC gate) vs research-program
   (peptide generator training, SDL) vs deferred (PIVOT branch). Use the ✅/🟡/🔧/🛑 convention.
6. **No benchmark self-criticism in a user-facing demo** — present the capability; keep the honest
   research caveats (cross-target) internal unless the audience is technical.

## Fixed
Advisory remediation (not auto-restart); never-automate-synthesis; the generator moat is our
own trained diffusion/LLM (AF3/Boltz are structure predictors used as commodity); peptides
first-class alongside small molecules.
