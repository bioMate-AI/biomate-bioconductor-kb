# BioMate × Guangzhou AI Drug Discovery Project

## Full platform capability and project-fit audit

**Prepared:** 2026-09-11  
**Opportunity:** *AI Drug Discovery Project — Molecular Generation and Optimization*  
**Scope:** BioMate's complete drug-discovery system—not only its interactive molecule-generation page.

## Executive assessment

BioMate has the functional capability required for this program. It is a **target-to-decision, Design–Make–Test–Analyse (DMTA) operating platform**: target evidence and structure, focused chemical-space design, predictive and physics-based evaluation, developability/safety/synthesis assessment, multi-objective campaign optimization, experimental feedback and an auditable decision record are designed to operate together.

The correct offer is therefore a **target-specific integrated discovery system**, configured around the company's target product profile, data, models and experimental decision rules. It is not a generic “molecule generator demo.”

The earlier version of this document was wrong in treating the conservative `/api/generate` user interface as the boundary of the product. That interface intentionally exposes only a limited set of honest RDKit objectives. It is one safe entry point into a much larger drug-discovery platform.

## BioMate's system advantage

Most discovery groups operate separate products for chemical design, docking, ADMET, synthesis planning, assay tracking and spreadsheets. BioMate supplies the governed integration layer across them:

1. **Scientific context:** target biology, omics, structure and literature evidence are available before chemical decisions are made.
2. **Computational design and evaluation:** a portfolio of drug-discovery and pharmacology workflows supports the full funnel from rapid library triage through physics-based refinement.
3. **Campaign intelligence:** model adapters, measured assay data, Bayesian multi-objective optimization, Pareto selection and diversity-aware next-batch proposals act on one compound series.
4. **Execution governance:** inputs, parameters, model/workflow versions, QC gates, provenance, human decisions and overrides are recorded rather than being hidden behind a score.
5. **Experimental handoff and learning:** synthesis/availability/CRO outputs and assay ingestion connect computational recommendations to the next design round.

BioMate's value for the company is not just “an AI predicts molecules.” It provides a reusable, auditable operating system in which the company keeps its data, models, thresholds and scientific authority.

## Requirement-to-platform map

| Guangzhou requirement | BioMate capability | Use in the project |
|---|---|---|
| Molecular structure–bioactivity learning | Partner-data QSAR Random Forest workflow; custom Python/Docker/REST model registry; applicability-domain support; structured assay ingestion and campaign memory. | Train or connect the company's validated activity/selectivity models; establish temporal or external holdout performance before using them in lead selection. |
| AI molecular generation | Focused analogue enumeration, BRICS, scaffold decoration/hopping, RECAP/MMP design, pharmacophore filtering, covalent-warhead design, novelty/diversity filters, optional BioNeMo GenMol/MolMIM integration and partner-model adapters. | Generate a diverse, constraint-aware virtual library from the starting series, scaffold and target product profile. |
| Target affinity and selectivity | Pocket/druggability analysis; structure workflows; AutoDock Vina, DiffDock and licensed Glide; DrugCLIP virtual screening; anti-target/proteome selectivity profiling; OpenFE RBFE, GROMACS/AMBER MD and MM-GBSA. | Apply a tiered funnel—rapid screen → docking/pose inspection → selective high-cost refinement—then compare with the assay hierarchy. |
| Synthetic accessibility | SA scoring, AiZynthFinder route planning, SynCraft synthesis-oriented structural edits, PubChem identity/availability check and CRO-ready export. | Make route, cost, building-block and chemistry constraints explicit while choosing the shortlist and preparing synthesis. |
| Safety and properties | Physicochemical profiling; Lipinski/Veber/Egan; ADMET-AI/Chemprop path plus structural/RDKit safety filters; hERG, DILI, Ames/genotoxicity, CYP/transporter/DDI, permeability, CNS, clearance and exposure workflows. | Treat developability and safety as visible gates/objectives alongside potency—not post-hoc labels. Use predictions for prioritization, then verify in the planned assays. |
| Multi-property candidate ranking | Objective-specific GP surrogates, hypervolume-improvement acquisition, Pareto front, diversity penalty, configurable measured-assay ranking and confidence/applicability signals. | Select a defensible batch across potency, selectivity, safety, exposure, novelty, synthesis and portfolio diversity without concealing trade-offs in one opaque score. |
| Integrated end-to-end process | Campaign API/UI, Nextflow execution, QC/provenance, assay/report ingestion, CRO export, retraining controls, Benchling integration point, audit and electronic-signature surfaces. | Run every round from a shared project record and retain the exact evidence that supports each compound decision. |

## The DMTA workflow BioMate enables

```text
Target product profile, disease/omics evidence and project data
  → target structure, pocket/druggability and target/anti-target review
  → focused chemical-space generation / enumeration / virtual screening
  → activity-QSAR + docking + selectivity + ADMET + property evidence
  → MD/MM-GBSA or RBFE refinement for the highest-value series
  → synthesis feasibility, commercial options and diversity-aware Pareto shortlist
  → CRO synthesis package and experimental assay plan
  → assay/DMPK results with units and provenance
  → campaign re-ranking, approved model update and Bayesian next-round proposal
```

Core implementation evidence:

- `bayesian_optimizer.py` implements per-objective Gaussian-process surrogates, hypervolume improvement, diversity-aware selection and Pareto proposals.
- `assay_ingestion.py` and `assay_schema.py` parse and normalize experimental assay results into campaign rankings.
- `custom_model_registry.py` and `custom_model_wrapper.py` accept in-house models as a Python function, Docker workload or REST service.
- `commercial_availability.py` and `cro_order_export.py` provide identity/availability checking and WuXi, Pharmaron, Enamine or generic order packages.
- `api_router.py`, `auto_retrain.py`, `feedback_io.py` and `benchling_connector.py` provide campaign, feedback and automation integration points.

## Breadth beyond the immediate lead-optimization scope

The published request is early discovery/lead optimization. BioMate can connect it to the upstream and downstream evidence needed by a pharmaceutical organization:

- **Target discovery/validation:** WGS/WES, RNA-seq, single-cell, GWAS, epigenomics, proteomics and cryo-EM workflows help establish target biology, disease context and tractability.
- **Mechanism/selectivity:** chemoproteomics, phosphoproteomics, drug-treated RNA-seq / MoA workflows and target/anti-target analysis support target-engagement and mechanism hypotheses.
- **Translation:** NCA, PopPK, PK/PD, PBPK, IVIVE, exposure-response and safety pharmacology can extend a selected series toward preclinical decisions.
- **Scientific workspace:** conversational workflow planning, literature/evidence support, methods/QC reports, results viewers and notebook handoff reduce friction across computational chemistry, medicinal chemistry, DMPK, biology and CRO teams.

## Verification status—precise, not narrow

The platform contains **53 drug-discovery workflow modules and 55 pharmacology modules**. This is genuine scope, but a responsible project plan distinguishes capability from a particular deployed runtime:

| Evidence level | What the review found | Meaning for the project |
|---|---|---|
| Local/container proof | The 2026 Docker E2E audit records 40/40 checks across RDKit, GP/HVI selection on 16 real drugs, BCR-ABL assay ingestion/ranking, CRO export, PubChem identity lookup, QED and AiZynthFinder runs. | Strong evidence for core campaign mechanics; reproduce in the agreed project environment. |
| Workflow implementation | Full source workflows are present for design, screening, docking, ADMET, retrosynthesis, MD, PK/PD and translational analysis. | Configure the subset needed for the target and deploy required containers/models/licences. |
| Historical executed workflows | Prior records document completed validation of selected ADMET, DDI, PBPK, pocket, pharmacophore, clinical-trial and virtual-patient workflows. | Useful starting evidence, but not a blanket statement that every workflow is current-dev validated. |
| Current deployment evidence | A recent dev ADMET run completed its compute steps, but its six output artifacts returned storage `403 InvalidAccessKeyId`; result contents and findings could not be verified through the application. | Fix output signing/access before using current dev as a partner proof environment. |

Known dependencies are ordinary deployment work, not missing product scope: GPU/container image availability for selected workflows, model assets for AiZynthFinder and learned generators, vendor licences such as Glide, customer model/service credentials, and the project's data governance requirements.

## Important technical precision

- The workflow named `reinvent4_lead_design` currently implements transparent RDKit/BRICS enumeration and filtering; it is not REINVENT reinforcement learning. A learned generator is available as a BioNeMo integration point or through the customer model registry. The company should choose and qualify the desired generator in Phase 1.
- Docking, ADMET and retrosynthesis are decision-support evidence. BioMate is designed to compare and combine them with project data and expert review; it does not claim that they replace medicinal chemistry, synthesis, safety assays or efficacy studies.
- The existing live Benchling and browser assay-upload paths require integration hardening before being represented as hands-free production feedback: connector field mapping and multipart forwarding need verification. CSV/API assay ingestion and campaign mechanics are present.
- PubChem identity lookup is live; direct Enamine/Sigma vendor API availability is not configured, so it must not be described as confirmed live vendor inventory.

## Recommended project structure

### 1. Target and data activation

Confirm target, indication, modality, binding hypothesis, target product profile, known liabilities, assay hierarchy, chemical-series constraints and partner data rights. Activate the agreed structures, historic activity/selectivity/DMPK/synthesis data, reference libraries and approved external or in-house models.

### 2. Target-specific computational benchmark

Run pocket/structure review; establish docking/redocking and ligand-model baselines; train/evaluate QSAR on predeclared splits; configure ADMET, selectivity and synthesis gates; choose the decision contract and baseline process.

### 3. Prospective DMTA campaign

Generate/enumerate focused compounds; evaluate activity, selectivity, developability, safety, novelty and synthesis evidence; deliver a transparent Pareto shortlist; export a chemistry/assay package; ingest observed data and quantify prediction-to-measurement performance.

### 4. Program scale-out

Extend to new series or targets, connect approved ELN/LIMS/CRO services, deploy the selected model stack in the company's preferred environment and curate reusable model/workflow templates.

## Audit against the actual client questionnaire

This section audits BioMate against the **actual 20-question Chinese technical clarification list**, not an invented start-up checklist. The Chinese original is [20260909_AI_DRUG_MOLECULE_GEN_QUESTIONS_ZH.md](/Users/kky/biomate/docs/20260909_AI_DRUG_MOLECULE_GEN_QUESTIONS_ZH.md); its faithful English reference is [20260911_GUANGZHOU_CLIENT_QUESTIONNAIRE_EN.md](20260911_GUANGZHOU_CLIENT_QUESTIONNAIRE_EN.md).

| Client question group | What BioMate already provides | What must be configured with the company |
|---|---|---|
| Q1 modality: small molecule, peptide/macrocycle, PROTAC, molecular glue | Small-molecule design is broad and production-facing. Peptide/protein and PROTAC-related workflows exist in the wider workflow portfolio. | Select the modality-specific representation, generator, evaluators and acceptance benchmark. Do not present a single small-molecule generator as universal coverage. |
| Q2 target classes and structure-/ligand-based design | Target evidence, AlphaFold/PDB structure search, pocket/druggability, docking/MD/RBFE, ligand/QSAR/pharmacophore/virtual-screening workflows. | Define target, structure confidence, pocket hypothesis, known ligands and assay hierarchy. |
| Q3 single versus multi-target design | Explicit multi-objective GP/HVI/Pareto ranking, anti-target/selectivity workflows and configurable objective inputs. | Specify target/anti-target panel, directionality, hard gates and trade-offs. |
| Q4 self-service expansion to new targets | Configurable workflow/campaign layer, custom model registry and reusable workflow templates. | Agree the governance boundary: which target setup is self-service and which needs expert model/workflow qualification. |
| Q5 pretrained versus company-data models | General workflows plus custom Python, Docker and REST model adapters; assay ingestion and retraining controls. | Establish data inventory, rights, quality/QC rules, splits, applicability domain and prospective validation. |
| Q6 ELN, compound library, database and LIMS integration | API/campaign architecture, CSV/API ingestion, CRO exports and a Benchling integration point. | Map partner schemas and authentication. Browser multipart and Benchling field-mapping paths need production hardening before promising hands-free integration. |
| Q7 ownership of compounds, models and workflows | Provenance, versioning and deployment controls preserve evidence and ownership boundaries. | Contractually define foreground IP, model ownership, data-derived improvements and access rights; software cannot decide this. |
| Q8 configurable multi-objective optimisation | Separate potency/affinity, ADMET, safety, synthesis, novelty and diversity objectives; GP/HVI/Pareto selection. | Configure ranges, weights, exclusions and who may override them for each target product profile. |
| Q9 standard safety scope | hERG, DILI, Ames, CYP/DDI, permeability, CNS, clearance/exposure and structural filters are present as workflows. | Select required endpoints and use predictions only for triage until confirmed by the agreed assay plan. |
| Q10 synthesis feasibility and novelty/FTO | SA scoring, AiZynthFinder, SynCraft, similarity/novelty filters, PubChem identity checks and CRO order export. | Define chemistry constraints and use specialist patent/FTO review; live commercial inventory is not currently configured beyond PubChem identity lookup. |
| Q11 computational versus wet-lab DMTA loop | Campaign records, assay ingestion, feedback I/O, retraining controls and Bayesian next-round selection. | Choose the desired operating model and integration level. |
| Q12 who makes/tests and what cadence | CRO-ready order packages and a configurable campaign sequence. | Partner supplies laboratory/CRO, throughput, cycle-time, material/QC and assay commitments. |
| Q13 result ingest and model update | Assay schema/ingestion, campaign re-ranking, versioned retraining and custom model adapters. | Define data-transfer format, validation rules, automatic versus reviewed updates, and retraining acceptance criteria. |
| Q14 explore/exploit and human gate | Uncertainty-aware Bayesian acquisition, diversity penalty, Pareto selection, QC gates and decision provenance. | Set exploration/exploitation policy, batch size and human approval checkpoints. |
| Q15 partial results and provenance | Structured ingestion, failed/partial-result handling, workflow/model/parameter provenance, QC/audit surfaces. | Agree censoring semantics, failure codes and retention/audit requirements. |
| Q16 platform versus one-off delivery | BioMate is a reusable platform with interfaces, workflow configuration and governance; it can also support milestone packages. | Resolve commercial delivery model and budget allocation. |
| Q17 benchmark and acceptance | Historical/retrospective evaluation flows, run reports and auditable model/workflow evidence. | Predeclare benchmark data, splits, metrics and prospective decision criteria; no scientifically credible acceptance criterion is generic. |
| Q18 deployment, residency and secure stack | Deployable workflows, containerised/custom model options, audit/access-control surfaces. | Choose cloud/private/on-premises architecture, identity, data-residency and domestic-stack constraints. |
| Q19 users and operating scale | Scientist-facing conversational workflow planning, viewers, reports and governed review paths. | Size compute, concurrency, permissions and UI role design around real user groups and campaign volume. |
| Q20 MVP versus final delivery and milestones | The platform can be phased from target/data activation through a benchmark and prospective DMTA campaign to scale-out. | Confirm the 2026-12-31 meaning and milestone acceptance gates. |

## Partner-facing description

BioMate is an AI-enabled drug-discovery operating platform that connects target evidence, molecular design, structure-based and data-driven evaluation, developability and safety assessment, synthesis planning, experimental feedback and multi-objective decision-making. It turns a partner's target product profile and data into a governed DMTA workflow: every candidate remains connected to its structure, predicted and observed evidence, model/workflow version, QC result and scientific rationale.

For this program, BioMate will configure a target-specific molecular generation and optimization system. It will integrate the company's data and scientific decision criteria with BioMate's computational and campaign portfolio to produce diverse, synthesis-aware, safety-aware and evidence-ranked candidate series; then improve them through measured assay feedback. The outcome is a reusable company discovery capability, not a one-time molecule list.
