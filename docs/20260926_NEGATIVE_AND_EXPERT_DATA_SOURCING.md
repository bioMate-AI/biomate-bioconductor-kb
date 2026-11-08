# Mining Negative Outputs + Expert Feedback for the Loop — Sourcing & Ingestion Plan

**Date:** 2026-09-26
**Question:** where do we mine the negatives + expert feedback that feed the generate→verify→learn loop? (literature? patients? …)
**Answer in one line:** measured negatives come from **public bioactivity DBs** (biggest, cheapest); expert feedback comes from **patents joined to clinical phase** + **MMP-SAR** + **MolSkill** + **rule bases**; **patients are downstream** (safety/efficacy weak-labels, not the chemistry loop's negatives). The compounding moat is the **customer's own** wet-lab negatives + chemists' accept/reject.

---

## Part 1 — Measured negatives (inactives / non-binders / tox failures)

| Source | Mineable negatives | Access / filter | License | 3D? |
|---|---|---|---|---|
| **ExCAPE-DB** ⭐ | ~tens of M (pre-labeled) | Zenodo `10.5281/zenodo.2543724`; filter `Activity_Flag=='N'` | CC BY-SA 4.0 | no |
| **PubChem BioAssay** | tens of M `Inactive` (of >130M outcomes) | FTP `Bioassay/Concise/CSV/`; filter `PUBCHEM_ACTIVITY_OUTCOME=="Inactive"` | **Public domain** | no |
| **ChEMBL** | millions | FTP SQLite; `activity_comment IN('Not Active',…)` OR `standard_relation='>'` (censored) OR null-pchembl>thr | CC BY-SA 3.0 | no |
| **BindingDB** | censored/weak affinities | Download.jsp / REST; `>`-prefixed Ki/Kd | CC BY 3.0 (curated) | **partial (3D SDF)** |
| **Tox21 / ToxCast** | millions (`hitc==0`) | EPA figshare / invitrodb; `hitc==0` | **Public domain** | no |
| **hERG / DILIrank** | ~1–2k gold negatives | Zenodo / TDC; `label==0` / `vNo-DILI-Concern` | CC BY 4.0 / PD | no |
| **FAERS** | weak safety signal only | openFDA; needs disproportionality (ROR/PRR) | **Public domain** | no |
| DUD-E / DEKOIS / DeepCoy | synthetic decoys | dude.docking.org / generate | academic/open | poses/gen |

**Top-3 mine-first:** ExCAPE-DB (least ETL) → PubChem (volume) → ChEMBL (richest structured). BindingDB if you need measured 3D.

**Caveats:** HTS "inactive" ≠ confirmed non-binder (insoluble/aggregated/below-conc — prefer confirmatory/dose-response AIDs); assay heterogeneity (right-censored `>` is inactive only *relative to the tested ceiling* — store the ceiling); **measured ≠ synthetic** — train on measured, keep DUD-E/DEKOIS decoys **eval-only** (they teach "decoy-ness," not binding); **no 3D anywhere except BindingDB (partial)** → generate conformers/poses (ETKDG/dock) or keep negatives at the property-head level (where they matter most).

---

## Part 2 — Expert feedback (medchemist design decisions)

| Source | Signal | Access | License |
|---|---|---|---|
| **Patents × clinical phase** ⭐ (the crown jewel) | advanced-vs-abandoned design *choice* | SureChEMBL Parquet (EBI FTP) ⋈ ChEMBL `max_phase` | CC BY-SA (internal-train OK) |
| **PatCID** | pre-extracted patent structures (wider geo) | GitHub `DS4SD/PatCID` + Zenodo 10572870 | CDLA-Sharing |
| **mmpdb (MMP-SAR)** | "which edit helps" transform prior | `pip install mmpdb` over ChEMBL | **BSD** |
| **MolSkill** | chemist "taste" scorer (35 Novartis chemists) | `microsoft/molskill` (conda) | **MIT** |
| **Rule bases** | guardrails | RDKit `FilterCatalog` (PAINS/BRENK/Glaxo…), Lilly-Medchem-Rules, QED | BSD / Apache-2.0 |
| Derek / StarDrop / CAS / Reaxys | curated tox/chemistry | subscription | proprietary (offline oracle only) |

**The crown jewel — advanced-vs-abandoned DPO pairs:** join SureChEMBL patent compounds to ChEMBL `max_phase`. **Positive** = advanced (`max_phase≥2`, elite `=4` marketed) — a sponsor *chose* to progress it = revealed expert preference. **Negative** = patent-only, never advanced (~99% of patent compounds). **Best framing = within-patent hard negatives:** the compound that advanced vs near-analog congeners in the *same Markush claim* that didn't — isolates the med-chem *choice* with target/era/assignee held constant. Published recipe: `github.com/Fraunhofer-ITMP/patent-clinical-candidate-characteristics` (Sci Data 2024). *Honest caveat:* patent-only negatives are noisy (may have advanced privately) → weak negatives; lean on within-patent pairs + `max_phase≥2` positives for clean signal.

**Structure extraction (if re-mining patents):** DECIMER / MolScribe (image→SMILES, MIT), OPSIN (name→structure), ChemDataExtractor (text/tables).

---

## Part 2b — Physicochemical data (the third pillar)

**Why high-leverage:** **target-agnostic** — a solubility/permeability/logD model transfers to *any* new target's chemistry, so it's the single best answer to the **new-target-generalizability pain**. Computable from structure (RDKit/Mordred, no assay), measured sets are large + **calibration-grade**, and for peptides it's *the* developability driver (permeability/3D-PSA/lipophilicity). It's the **"physical" leg** alongside biological (activity/negatives) and expert (patents).

| Property | Dataset(s) | ~Scale | Access | License |
|---|---|---|---|---|
| **Aqueous solubility** | AqSolDB, ESOL, MoleculeNet | ~10k / ~1.1k | TDC / Dataverse / MoleculeNet | permissive (CC0/MIT) |
| **Permeability** | Caco-2, PAMPA (NCATS), MDCK; **CycPeptMPDB** (peptides) | ~1k–10k | TDC `ADME`; CycPeptMPDB | permissive |
| **Lipophilicity (logD/logP)** | MoleculeNet Lipophilicity, ChEMBL logD, OChem | ~4.2k / large | TDC / ChEMBL / OChem | MIT / CC-BY-SA |
| **pKa** | curated pKa sets, DataWarrior | ~1–10k | public | mixed |
| **Bundled ADME** | **TDC ADME suite** (20+ tasks: sol/perm/logD/PPBR/…) | — | `pip install PyTDC` | permissive |
| **Computed descriptors** | RDKit / Mordred | infinite | pip | BSD |

**We already use:** EnsembleCycPerm ΔPSA3D (permeability), CycPeptMPDB, descriptor featurizations, QED/Ro5. **Gap:** the broader *measured* sets aren't ingested to calibrate the ranking-grade heads (permeability ~R²0.23 partly for this reason), and physchem is applied **post-hoc** (verify/guidance), not **baked into generation**.

## Part 3 — Where "patients" fit (honest)
Patient data is **downstream and indirect** for the chemistry loop:
- **FAERS / clinical failures** → chemotype-level *safety* weak-labels ("this scaffold failed in humans"). Coarse but real.
- **Patient response / PDX / biomarkers** → feed the **target & stratification** layer (the immune-LLM program), **not** the molecule generator's negatives.
- So patients answer "did the *drug* work in people," not "does this *molecule* bind/behave." Use them for the target/efficacy side, not the chemistry-negative loop.

---

## Part 4 — Ingestion plan (source → our A1 / A2 / DPO pipeline)

- **A1 verify / property heads** ← measured negatives train calibrated heads: ExCAPE/ChEMBL/PubChem inactives → affinity/permeability heads; Tox21/ToxCast/hERG/DILIrank → safety heads. (Fixes verify's "safety is a stability proxy" gap with real tox negatives.)
- **A1 physchem calibration** ← measured physicochemical sets (AqSolDB/ESOL solubility, Caco-2/PAMPA/MDCK permeability, MoleculeNet/ChEMBL logD — bundled in TDC-ADME) calibrate the permeability/solubility/logD/tox heads (turns ranking-grade → calibrated). **Best lever for new-target generalizability** — these transfer target-agnostically. RDKit/Mordred descriptors as free features for the surrogate + applicability domain.
- **DCG-P1 (generation)** ← physchem learned heads *condition sampling* (bake permeability/SA into the generator, not just post-hoc verify) — replaces the P0 geometric proxies in `developability_guidance.py`.
- **A2 select** ← rule guardrails as filters/penalties: **hard reject** = BRENK + CHEMBL_Glaxo + Lilly 100-demerit; **soft** = QED↑, PAINS↓, Lilly-demerits↓, Ro5/Veber↓. mmpdb transform prior weights proposed edits.
- **A4 DPO (the generator)** ← two preference streams:
  1. **Activity DPO:** active ≻ inactive pairs from measured DBs → steer generation away from inactive regions.
  2. **Expert DPO (crown jewel):** advanced ≻ abandoned within-patent pairs → steer toward expert-chosen designs.
  3. **MolSkill** reward term, **fine-tuned on the customer's own accept/reject logs** (the moat), same `(chosen≻rejected)` contract.

**Composite loop reward** (all open, testable): `+β·QED − γ·PAINS − δ·(Lilly_demerits/100) − ε·Ro5 + mmpdb_prior + w·(−MolSkill) + DPO(activity) + DPO(advanced-vs-abandoned)`; hard-gate BRENK+Glaxo+Lilly-reject.

---

## Part 5 — Commercial-license posture (important for a product)
- **Cleanest for commercial (public domain / CC-BY / permissive):** PubChem, Tox21/ToxCast, FAERS, BindingDB (curated), hERG/DILIrank; and mmpdb, MolSkill, RDKit filters, Lilly rules (BSD/MIT/Apache-2.0).
- **CC-BY-SA (ShareAlike) — ChEMBL, ExCAPE, SureChEMBL; CDLA-Sharing — PatCID:** copyleft bites **only on redistributing the derived data/rule tables**, **not** on using the signal to train internally. So: *train on them freely; don't ship the derived dataset.*
- **Exclude from the loop:** Derek/StarDrop/CAS/Reaxys/Lens (proprietary, no ML/bulk rights) — usable only as an offline oracle on a short candidate list.

**Mine-first, commercial-safe ordering:** PubChem inactives (PD) + Tox21/ToxCast (PD) for the property/safety heads; SureChEMBL×max_phase for the expert-DPO (internal-train only); MolSkill + Lilly/BRENK/QED for taste + guardrails — then layer the customer's proprietary negatives + accept/reject as the compounding moat.
