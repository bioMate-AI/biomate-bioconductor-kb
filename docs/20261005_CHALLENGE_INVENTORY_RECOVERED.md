# Cyclic-Peptide / Drug-Discovery Challenge Inventory (Recovered Audit)

**Date:** 2026-10-05 · Grounded audit of ALL prior work per identified challenge, so the body of work
is not lost / under-counted. Status vocabulary: designed / built / synthetic-verified /
validated-with-results / gated / plateaued. Source: full `docs/` + `research/guangzhou_all_atom/` sweep.

**Program's own honest framing (recurring):** the defensible contribution is the integrated
closed-loop SYSTEM + proprietary data + prospective validation — NOT "we beat SOTA." Every
"generalization"/"SOTA" win is in-silico-only or imported from physics priors.

## Summary table — challenge → best artifact(s) → status → key number
| Challenge | Best artifact(s) | Status | Key result/number |
|---|---|---|---|
| Novel-target generalization (physics prior) | `launch_rfpeptides.sh` + `20261004_RFPEPTIDES_SETUP.md` | **BUILT + locally verified, NOT launched** | 0 results; preflight OK only; lit bar 12/39 binders @9.4nM |
| Novel-target binding OOD eval | `binding_model_metrics_*.json`, `20261004_BINDING_MODEL_RESULTS.md` | **Validated-with-results (NEGATIVE)** | in-dist Spearman 0.736; PD-L1 hold-out **0.18** |
| Target-ranker generalization (separate subsystem) | `target_scorecard_ranker/main.nf`, `20260727_*SCORECARD*` | **Validated-with-results** | 16/16 + 16/16 live runs; ERBB2 #24→#1 fix |
| Cold-start designability | `speed_surrogate.py`, `speed_surrogate_loto.json` | **Within-target validated; cold-start plateaued** | ~43% PD-L1 co-folds saved @80% recall; LOTO 1u8p 0.44 |
| Expert/wet-lab DPO close-back | `dpo_peptide_trainer.py`, `dpo_unimomo_adapter.py`, `simulate_closed_loop.py` | **Built + SYNTHETIC-verified; GATED (G6/G7)** | self-tests green; only VERIFY_SELECT pairs; no real KD |
| DBTL/DMTA platform loop | `dbtl_controller.py`, `bayesian_optimizer.py`, `20260417_WETLAB_MODEL_FEEDBACK_LOOP.md` | **Built (simulated); designed gaps** | self-assessed "loop completeness 40%"; BO not API-wired |
| Expert/negative data sourcing | `20260926_NEGATIVE_AND_EXPERT_DATA_SOURCING.md` | **Designed only** | SureChEMBL×ChEMBL within-patent advanced≻abandoned; MolSkill; measured negatives |
| CRO DBTL feedback data spec | `20261001_CRO_DBTL_LOOP_DATA_SPEC.md` | **Spec built; no real KD returned** | structured KD/sensorgrams + non-binders as hard negatives |
| Regulatory-LLM feedback loop (separate) | `20260517_V6_LIVE_FEEDBACK_LOOP_...md` | **Built + synthetic-eval; OOD gated** | 4/5 checkers above target; OOD blocked |
| Multi-objective selection | `mo_select_qnehvi.py`, `mo_qnehvi_rescore.json` | **Built + validated-with-results** | greedy-HV +115%, qNEHVI +37.6% vs composite (PD-L1) |
| Data scarcity | `binding_affinity_v1`, CycPeptMPDB, CREMP, `cyclic_data_registry.yaml` | **Have (real)** | 136,730 binding rows (36,102 cyclic); CREMP 36,198; perm 8,466 |
| Integrated pipeline | `cyclic_pipeline_manifest.yaml`, `peptide_loop.py` | **Built; 7/9 gaps closed, 2 open** | G6+G7 OPEN → loop doesn't compound on real data |
| Permeability | `permeability_predictor.py`, `build_physchem_calibration.py` | **Built + validated; OOD weak** | gate R²~0.45; OOD R²≈0.19 |
| Generator DockQ (SOTA) | cyclic-FT ckpt, `cyclic_official_metrics.txt` | **Built, plateaued** | DockQ 0.506 vs UniMoMo ~0.759 |
| Selectivity | — | **Identified, not built** | omitted from MO (single-target data) |
| Safety/tox | `stability_predictor.py` (proxy) | **Honest proxy only** | no real tox oracle |

## CORRECTION (2026-10-06): expert KNOWLEDGE *was* mined (don't say "no expert signal")
Real mined expert signal exists and is IN BIOMATE: `backend/scripts/domain_knowledge/expert_knowledge_*.json`
(6 domains, ~650 KB) — LLM-extracted from tool docs/literature/guidelines (`batch_llm_extract.py`,
`extract_all_scientific_context.py`, `extract_biomni_tool_usage.py`; plan
`backend/20260209_BIOMATE_EXPERT_KNOWLEDGE_LEVERAGE_PLAN.md`), human-reviewed (`review_*.md`), injected via
`inject_expert_knowledge.py`. This is a one-way knowledge INJECTION into the assistant/tool-use — distinct
from the expert PREFERENCE-pair FEEDBACK loop below. The two "expert signals" must not be conflated.

## Closed-loop expert-feedback (PREFERENCE pairs → DPO) — honest status (the critical caveat)
- **BUILT + SYNTHETIC-verified only** (wiring, not learning). "The close-back machine works; it is not
  yet fed real preference signal" — only VERIFY_SELECT pairs exist; ACTIVITY/EXPERT streams empty.
- **A single wet-lab round cannot validate or train it** — DPO needs many pairs; one round = one DBTL
  iteration, not proof of learning.
- **Heterogeneous feedback (structural critique, varied assay outputs) is DESIGNED, not built/validated**
  — only KD→pairs is implemented; the broader ingestion lives in `20260926` + the CRO spec as design.
- **Correct validation (doable NOW, not "wait for one case"):** retrospective, at scale, on the **136k
  real affinities** (`binding_affinity_v1`) + public display-NGS enrichment — hold out targets, feed real
  preference signal, show the generator/selector measurably improves. Only then is it trustworthy on new
  real feedback. Then wire the already-designed heterogeneous ingestion.

## Flags
- **CONFLICT to verify:** `dpo_unimomo_adapter.py` claims UniMoMo repro DockQ 0.7754, but
  `20261002_GENERATOR_DPO_TRAINER_DESIGN.md` says that run FAILED (MKL) + pending re-launch — treat 0.7754
  as UNCONFIRMED (no results artifact found).
- **Validated with REAL results:** binding model (136k, negative OOD), qNEHVI re-score, speed surrogate,
  cyclic-FT DockQ 0.506, BoltzGen panels, permeability predictor, MM-GBSA ΔG, target-scorecard live runs.
- **SYNTHETIC-verified only:** DPO trainers, UniMoMo adapter, simulate_closed_loop, wetlab_kd_to_pairs,
  campaign_assay_to_pairs.
- **DESIGNED only (no run):** RFpeptides full run, expert/negative-data ingestion, selectivity,
  cold-start inverse-folding lever, multi-modal joint accuracy model, target-pocket embedding.
- **GATED (external):** real CRO SPR KD (G6), checkpoint auto-promotion (G7), real-instrument actuation,
  regulatory OOD eval.

**Nothing is abandoned.** The program is paused at the two loop-closing seams (G6/G7) that need real
wet-lab data — but the closed loop's *learning* can and should be validated retrospectively on the real
data already held, rather than waiting on a single new case.
