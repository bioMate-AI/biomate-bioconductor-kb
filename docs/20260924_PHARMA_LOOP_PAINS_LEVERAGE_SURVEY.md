# Pharma Loop Pains → What BioMate Has, What to Leverage Now, What to Build

**Date:** 2026-09-24
**Trigger:** Pharma customer feedback — three pains: (1) can't accumulate experienced-medchemist knowledge, (2) models don't generalize to new targets, (3) internal data (esp. negative samples) underused.
**Basis:** internal code audit (file:line) + three external surveys (published methods + open-source, license-checked, honesty-flagged).

---

## 0. Headline

All three pains are symptoms of an **open-loop** pipeline — knowledge, generalization, and negatives all die in the **Learn** phase. BioMate already has an unusually complete **closed-loop (DMTA) scaffold** — the fix is to **upgrade components we already own and wire the Learn phase into the molecule generator**, not build from scratch. Most recommended tools are **Apache-2.0/MIT and several are already in the stack** (REINVENT4, DrugCLIP, a GP optimizer). The honest limiter: **prospective wet-lab validation of the closed loop has not been run** (per the 2026-09-22 committee review), and **cold-start to a truly novel target is an unsolved research problem** — we buy a *warm* start, not a free model.

Loop mapping: Pain 1 = **capture** expert judgment in Learn; Pain 2 = make generalization a **loop property** (specialize per target) not a static-model gamble; Pain 3 = feed **negatives** back into Learn (and into *generation*, not just ranking).

---

## 1. Pain 1 — Accumulating experienced-medchemist knowledge

**What BioMate has (code audit):**
- DPO preference-pair capture from customer edits (`drug_discovery/feedback_router.py:89`, `feedback_io.py:95`), audit-dismissal feedback, per-org rule compilation to preferred/banned phrases (`org_rule_compiler.py:89`), project-scoped long-term memory. **BUT all of this steers IND *narrative text*, not compound design.**
- Benchling connector exists but **mocks data** (does not capture expert annotations) — a blocker in the 2026-09-22 review.

**Leverage now (surveys, permissive):**
- **MolSkill** (MIT, Microsoft, *pretrained* on 35 Novartis chemists' pairwise choices) — drop-in "chemical-desirability" scorer for any SMILES today; later fine-tune on our own accept/reject logs. Highest value-per-effort.
- **REINVENT4** (Apache-2.0, *already in stack*) + **Metis** (MIT) — generator with a plug-in scoring interface + a ready-made chemist-feedback UI/reward loop (global + substructure-level annotations). Budget a small REINVENT4 adapter for Metis.
- **mmpdb** (BSD) + **RDKit FilterCatalog** + **rd_filters** (MIT) — encode/reuse SAR as matched-molecular-pair transforms + medchem alerts (PAINS/BRENK/ChEMBL) as guardrails/design suggestions, ~zero build cost.

**Build gap:** turn expert feedback into **structural SAR rules that steer compound design** (today it only steers text); real bidirectional Benchling ingestion.

**Loop phase:** Learn (capture) → biases Generate.

---

## 2. Pain 2 — Generalizability to new targets

**What BioMate has (code audit):**
- Target-agnostic **physics** (pocket detection `detect_pocket.py:10`, docking, MD/FEP PoC) — works on any target day-1, no per-target training.
- GP **BayesianOptimizer** (`bayesian_optimizer.py`, sklearn GP + Matérn), applicability-domain checking (`applicability_domain.py`), per-campaign auto-retrain (`auto_retrain.py`), pocket-conditioned generation (`developability_guidance.py`, P0 proxies).
- **Gap:** no transfer/warm-start — GP needs **≥16 measured compounds** (`n_initial=16` hard wall), no priors, no multi-task sharing.

**Leverage now (surveys, permissive):**
- **Chemprop** (MIT) — multitask-pretrain on a ChEMBL target panel, freeze D-MPNN encoder, fine-tune head on the new target's few points. Lowest-risk warm start, production-grade.
- **ADKF-IFT** on the **FS-Mol** harness (MIT) — SOTA-class few-shot QSAR whose deep-kernel **GP gives calibrated uncertainty** → doubles as the active-learning surrogate (bridges to the BO loop).
- **BoTorch multi-task GP + RGPE** (MIT) or **BayBE** (Apache-2.0, chemistry-native) — transfer-BO that warm-starts from related assays → **removes the n_initial=16 wall**. BayBE/Ax is a direct upgrade of the existing sklearn-GP optimizer (qEHVI/qNEHVI for multi-objective batch).
- **DrugCLIP** (MIT, *already in stack*) — pocket→library triage on a new target with a structure, no fine-tune (triage, not a quantitative oracle).
- **Physics baseline:** AutoDock Vina / OpenFE (Apache/MIT) — the fair zero-data reference; we already have docking/FEP.

**Honesty yardstick:** evaluate on **leakage-filtered, family-disjoint splits** (GEMS "CleanSplit") — most "generalizes to unseen targets" claims are benchmark artifacts (train/test similarity leakage). "New task" ≠ "new fold."

**Build gap:** wire warm-start (Chemprop transfer + transfer-BO priors) so a new target inherits from analogous prior programs; upgrade the surrogate to BoTorch/BayBE.

**Loop phase:** cold-start Generate/Verify with physics+priors → the loop specializes per target as data accrues.

---

## 3. Pain 3 — Using internal data, especially negative samples

**What BioMate has (code audit):**
- Ingests negatives/inactives/censored values correctly (`assay_schema.py`, right-censored `>50µM` handled), GP surrogate **learns from all data incl. inactives** (`bayesian_optimizer.py:305`), QC quarantine on failed assays. **This already beats most pipelines** (which discard inactives).
- **Gap:** negatives shape *ranking*, not *generation*; no hard-negative/DPO on the generator; failure *reasons* not captured (synthesis-failed vs tox vs off-target collapse into "low score").

**Leverage now (surveys, permissive):**
- **Extend DrugCLIP** (MIT, *already in stack*) to consume **measured inactives as explicit hard negatives** (today it only uses in-batch/decoy negatives), using the **HCL / iMolCLR** reweighting recipe; backfill sparse targets with **DeepCoy** (BSD) property-matched hard decoys. Converts thrown-away "did-not-bind" data into direct training signal — no new dependency.
- **DPO-on-SMILES via HuggingFace TRL `DPOTrainer`** (Apache-2.0) on the REINVENT4 checkpoints we already produce — assay active/inactive → preference pairs. *Do not adopt any molecule-DPO repo (all unlicensed/research); reimplement the small, well-understood loop on TRL.*
- **REINVENT4 REST/plugin scoring** (already in stack) → wire to the assay-ingestion service so a completed assay round feeds reward directly (closed-loop RL with cheap-vs-expensive curriculum).

**Caution:** synthetic decoys (DUD-E/DEKOIS) carry physchem/analogue bias → inflate AUC; they do **not** substitute for measured non-binders.

**Build gap:** failure-reason taxonomy fed back to Generate; generator-side hard-negative/DPO.

**Loop phase:** Learn (negatives as first-class signal) → Generate avoids known-bad regions.

---

## 4. Consolidated "leverage now" table

| Tool | License | In stack? | Pain | Role |
|---|---|---|---|---|
| **REINVENT4** | Apache-2.0 | ✅ yes | 1,3 | Feedback-consuming generator (plugin/REST scoring → assay service) |
| **DrugCLIP** | MIT | ✅ yes | 2,3 | Pocket→library triage; extend to measured hard negatives |
| **BayesianOptimizer → BayBE / BoTorch** | Apache/MIT | ⬆ upgrade | 2 | Chemistry-native multi-objective batch BO + transfer (RGPE) warm-start |
| **MolSkill** | MIT | ➕ add | 1 | Pretrained chemist-desirability scorer |
| **Metis** | MIT | ➕ add | 1 | Chemist-feedback UI + reward loop for REINVENT4 |
| **mmpdb / FilterCatalog / rd_filters** | BSD/MIT | ➕ add | 1 | SAR transforms + medchem alerts as guardrails |
| **Chemprop** | MIT | ➕ add | 2 | Multitask-pretrain → fine-tune warm start |
| **ADKF-IFT + FS-Mol** | MIT | ➕ add | 2 | Few-shot QSAR + calibrated-uncertainty surrogate |
| **HF TRL DPOTrainer** | Apache-2.0 | ➕ add | 1,3 | DPO-on-SMILES from accept/reject + actives/inactives |
| **DeepCoy** | BSD | ➕ add | 3 | Property-matched hard decoys to pad sparse inactives |
| **GEMS CleanSplit** | (eval) | ➕ add | 2 | Leakage-filtered eval discipline (honesty yardstick) |

---

## 5. Honest caveats
- **Wet-lab validation of the closed loop has NOT been run** (committee review 2026-09-22). Architecture + provenance discipline are real; the prospective loop is the moat and is unproven.
- **Cold-start to a novel fold is unsolved** — warm-start ≠ working model; validate only on family-disjoint, leakage-filtered splits.
- **Molecule-DPO literature is immature** — reimplement on TRL, don't adopt repos.
- **Negatives**: no turnkey "ingest measured inactives" tool exists — it's a technique to graft onto DrugCLIP (which we own).
- Expert rule systems (Derek/StarDrop/Meteor) are mature but **commercial** — buy-not-build.

---

## 6. Recommended phasing (all on components we own or a direct upgrade)
1. **Wire the Learn phase into generation** (highest leverage): REINVENT4 REST scoring ← assay ingestion; add MolSkill as a scoring component; stand up DPO-on-SMILES (TRL) on our own accept/reject + actives/inactives. → hits Pains 1 + 3.
2. **Negatives as first-class**: extend DrugCLIP with measured hard negatives (HCL/iMolCLR) + DeepCoy padding; add a failure-reason taxonomy. → Pain 3.
3. **Warm-start new targets**: Chemprop transfer + BayBE/BoTorch transfer-BO (kill the n_initial=16 wall); DrugCLIP triage; physics baseline; GEMS CleanSplit eval. → Pain 2.
4. **Expert-knowledge UI + SAR guardrails**: Metis feedback loop + mmpdb/FilterCatalog rules. → Pain 1.

Each phase is a real loop-closing increment; the moat is running it on the customer's proprietary data (their negatives + their experts' decisions), which compounds and can't be copied.
