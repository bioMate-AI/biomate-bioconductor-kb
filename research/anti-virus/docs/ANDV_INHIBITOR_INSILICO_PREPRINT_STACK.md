# ANDV inhibitor track — in silico preprint stack (BioMate Nextflow)

**Audience:** Authors replacing wet-lab claims with a **computational-only** bioRxiv-style resource narrative.  
**Companion:** `research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py`, `docs/20260509_ANDV_NEXTFLOW_PIPELINE_EXECUTION.md`, `research/anti-virus/docs/MANUSCRIPT_DRAFT_ANDV_CAMPAIGN.md`, `research/anti-virus/docs/ANDV_CAMPAIGN_LESSONS_LEARNED.md`.

Registry IDs below come from `docs/20260419_WORKFLOW_REGISTRY.csv` (2026-04-19 snapshot). Where a workflow exists under `backend/biomni_workflows/nextflow_nfcore/subworkflows/` but has **no** row in that CSV, the registry column is left blank—re-sync the registry before citing IDs in a submitted manuscript.

---

## 1. Workflow table (core ladder + optional extensions)

Paths are **on-disk** from the repo root. The Nextflow API accepts the same path **without** the `backend/biomni_workflows/` prefix (e.g. `nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf`), as in the runner script.

| Workflow (short name) | `nextflow_path` in repo | Registry id (if known) | Role in a computational-only story |
|----------------------|-------------------------|------------------------|-----------------------------------|
| Pocket detection + druggability | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf` | 12805 | Define binding sites and QC gates for docking boxes. |
| Pharmacophore library filter | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pharmacophore_filtering/main.nf` | 12804 | Ligand-set triage before ADMET/docking when reference actives + library are available. |
| Predict ADMET (MPNN path in runner) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf` | 10782 (duplicate catalog row 12826) | In silico safety / developability triage; outputs include `toxicity_report.json` (treat aggregates with the same caution as in `AUDIT.md`). |
| ADMET_pred (descriptor-only) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf` | 10761 | Lighter RDKit-based hERG/DILI-style readout when DeepPurpose is not required. |
| AutoDock Vina docking | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf` | 10773 (duplicate 12824) | Ranked poses and affinities **in silico**; not binding free energies. |
| GROMACS protein–ligand MD + MM-GB(SA) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf` | 12799 | Post-docking refinement: MD trajectories, **MM-GBSA** (and related outputs per workflow); **not** the same as MM-PBSA unless the bundled tooling explicitly reports PB; check `versions.yml` / workflow README. |
| REINVENT4 generative lead design | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf` | 12800 | Scaffold decoration / de novo suggestions for **hypothesis generation**; must be followed by ADMET + docking (or stricter physics) before any ranking claim. |
| Scaffold hopping (RECAP + MMP) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/scaffold_hopping/main.nf` | 10643 | Generative-adjacent **elaboration** from SMILES inputs (scaffold diversity narrative). |
| OpenFE RBFE (relative ΔΔG) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/openfe_rbfe/main.nf` | 12830 | **Optional** alchemical relative binding free energy between two defined ligands (GPU-heavy); feasible as a methods “stretch goal,” not a default campaign step. |
| AMBER pmemd MD (+ MMPBSA.py path) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/amber_pmemd_md/main.nf` | 12802 | Alternative MD / MM-GBSA-style pipeline for groups standardized on AMBER; resource-intensive. |
| NCA / PKNCA | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nca_pknca/main.nf` | 10642 | **PK from concentration–time tables**: NCA parameters when (synthetic or literature) PK data are supplied—**not** a substitute for measuring ANDV inhibitor PK. |
| nlmixr2 population PK | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/nlmixr2_population_pk/main.nf` | 10780 | **PopPK / PopPD placeholder**: only with **disclosed synthetic or external** PK datasets; frame as workflow demonstration, not ANDV clinical inference. |
| PBPK simulation (8-compartment) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pbpk_simulation/main.nf` | 12873 | **Mechanistic PK exploration** from physicochemical + clearance inputs; useful for “what-if” oral exposure narratives with explicit priors—not validation of a specific GP inhibitor. |
| Nanoparticle PK / biodistribution | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/nanoparticle_pk_biodistribution/main.nf` | 12867 | **Formulation PK narrative** (NP/LNP-style); optional; parameters are not ANDV-specific unless you supply a justified scenario. |
| LNP formulation optimization | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization/main.nf` | 12869 | **mRNA/LNP delivery toy model**; skip unless the preprint explicitly discusses nucleic-acid delivery; not required for small-molecule GP inhibition. |
| Exposure–response modelling | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/exposure_response_modelling/main.nf` | 12883 | **PK–PD linkage** on supplied E–R pairs (e.g. synthetic curves); supports “dose vs surrogate effect” discussion without clinical trial claims. |
| Exposure–response modeling (US spelling) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/exposure_response_modeling/main.nf` | — | Same intent as the row above; confirm which path is registered in your deployment. |
| hERG / cardiac safety QSAR | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/herg_cardiac_safety_qsar/main.nf` | 12877 | Cardiac liability **in silico** layer complementary to ADMET_pred. |
| DART / reproductive tox alerts | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/dart_toxicity_prediction/main.nf` | 12863 | Early safety **alerting** from structure; regulatory framing must stay qualitative. |
| Repeated-dose tox prediction | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/repeated_dose_tox_prediction/main.nf` | 12866 | Organ-level **alert** tiering from SMILES + optional projected Cmax—hypothesis only. |
| Apply VCOG-CTCAE grade | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/apply_vcog_grade/main.nf` | 10768 | **Veterinary CTCAE-style** grading of an adverse-event narrative input; useful only if the manuscript includes a structured tox narrative demo—not a human clinical trial outcome. |
| Clinical trial simulation (dose escalation) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/clinical_trial_simulation/main.nf` | 12874 | **Statistical operating-characteristics** toy for Phase I–like designs; must **not** be described as results of an actual ANDV trial. |
| Dose–response (Hill) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/biochemistry/dose_response/main.nf` | 10566 | Pedagogical / supplementary **curve** fit when parameters are supplied; do not fabricate “measured” IC50s for ANDV. |
| NONMEM PopPK | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nonmem_poppk/main.nf` | — | Optional PopPK path in repo; confirm registry and container profile before API execution. |
| PK simulation PBPK | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pk_sim_pbpk/main.nf` | — | Additional PBPK-style entry point in repo; align parameters with `pbpk_simulation` and disclosure norms. |
| Structure prediction + docking (AF3 / DiffDock / Vina) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/structure_prediction_docking/main.nf` | 10644 | **Heavy** alternative track (structure generation + blind docking); distinct from the Vina-only ladder in the runner script. |
| P0 PKPD semaglutide validation | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/p0_pkpd_semaglutide/main.nf` | 12828 | **Out of scope** for ANDV unless repurposed with entirely new priors; kept here so grep hits are not mistaken for ANDV defaults. |

---

## 2. Explicit “no wet lab” methods paragraph (for Methods / limitations)

This campaign, when framed as a **computational resource**, may rely on BioMate outputs that **stand in for** early discovery evidence as follows:

1. **Structural context:** pocket volumes, druggability scores, and docking boxes from fpocket-based detection (`12805`).  
2. **Ligand prioritization:** pharmacophore match counts (`12804`), docking scores and poses from AutoDock Vina (`10773`), and optional **post-docking** MD with **MM-GBSA-class** estimates from the GROMACS workflow (`12799`) when trajectories complete successfully.  
3. **ADMET / safety triage:** `predict_admet_properties` / `ADMET_pred` plus optional specialized layers (hERG QSAR, DART, repeated-dose alerts). These are **models**, not assays.  
4. **Generative chemistry:** REINVENT4 (`12800`) and scaffold hopping (`10643`) produce **candidates for further scoring**—not approved drugs or validated leads.  
5. **PK / PD as simulation:** NCA (`10642`), nlmixr2 PopPK (`10780`), PBPK (`12873`), exposure–response fits (`12883`), and dose–response curve utilities (`10566`) may illustrate **workflows** using **synthetic or literature-derived** inputs. They **cannot** substitute for measuring absorption, distribution, metabolism, excretion, or antiviral potency of ANDV GP binders.

BioMate outputs **cannot** replace: viral neutralization IC50/EC50, target engagement by biophysics, animal efficacy, human safety, or clinical outcomes. **Do not invent experimental potencies** or cite fabricated trial results. Any numerical “IC50” in a dose–response demo must be labeled as **illustrative parameters** or from **unrelated reference datasets**, never as measured ANDV inhibitor values unless tied to real deposited data with citations.

---

## 3. Orchestration: scripted ladder vs optional API steps

### 3.1 Scripted steps 1–6 (recommended default)

The batch runner already implements `--through-step` **1–6** with `POST /api/nextflow/execute`. See `docs/20260509_ANDV_NEXTFLOW_PIPELINE_EXECUTION.md` for prerequisites (API key, S3 inputs, downloads for `--use-top-pocket-box`).

**Step 5 — GROMACS + MM-GBSA:** supply a ligand on S3 (e.g. docked pose exported as SDF/MOL2). Example pattern:

```bash
python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --pdb-input s3://YOUR_BUCKET/path/receptor.pdb \
  --through-step 5 \
  --reference-actives-s3 s3://YOUR_BUCKET/path/actives.smi \
  --compound-library-s3 s3://YOUR_BUCKET/path/library.smi \
  --use-top-pocket-box \
  --ligand-s3 s3://YOUR_BUCKET/path/top_pose.sdf \
  --gromacs-n-steps 500000 \
  --step-timeout 14400
```

Use a **short** `--gromacs-n-steps` (and generous `--step-timeout`) for smoke tests; production MD remains expensive.

**Step 6 — REINVENT4:** pass a seed SMILES and optional scoring mode; receptor-aware scoring requires the same `--pdb-input` URI the API accepts:

```bash
python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --pdb-input s3://YOUR_BUCKET/path/receptor.pdb \
  --through-step 6 \
  --seed-smiles "c1ccc2c(c1)ccc(=O)o2" \
  --reinvent-mode scaffold_decoration \
  --reinvent-n-steps 200 \
  --reinvent-scoring qed_sa
```

For `--reinvent-scoring docking_gnina`, keep `--pdb-input` pointed at the receptor on S3 so the workflow can consume it (see script `build_parameters_for_step`).

### 3.2 Optional extensions (manual API or future script)

PK/PD, PBPK, tox-alert, and RBFE workflows are **not** wired into `run_andv_inhibitor_pipeline_nextflow.py` by design (parameter contracts differ per workflow). Mirror the runner’s pattern: same `post_execute` body shape (`nextflow_path`, `parameters`, `workflow_domain`), poll status, archive manifests under `research/anti-virus/runs/`. When adding automation, extend the existing script only if the new step’s inputs are stable and failure modes are bounded—otherwise keep **documentation + copy-paste JSON** as the supported path.

---

## 4. Narrative ordering (suggested figure flow)

1. Pocket + pharmacophore → **target-consistent** ligand set.  
2. ADMET + optional tox-alert layers → **safety funnel**.  
3. Vina → **poses** for figures.  
4. (Optional) MD + MM-GBSA → **stability / rescoring** narrative.  
5. (Optional) REINVENT4 / scaffold hopping → **generative** hypotheses, fed back through steps 2–4.  
6. (Optional) PBPK / NCA / nlmixr2 / E–R → **synthetic-data** PK–PD “methods showcase” appendix, clearly disjoint from antiviral potency claims.

This ordering aligns with `MANUSCRIPT_DRAFT_ANDV_CAMPAIGN.md` as a **resource** paper: workflows + manifests first, biological validation only if real data are added later.
