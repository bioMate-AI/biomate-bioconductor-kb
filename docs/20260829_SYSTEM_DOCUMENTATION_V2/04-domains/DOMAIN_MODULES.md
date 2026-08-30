# 04 · Scientific Domain Modules

**Verified 2026-08-29.** Source: `backend/lib/galaxy/ai/`, `backend/lib/galaxy/webapps/galaxy/api/`, and `backend/biomni_workflows/nextflow_nfcore/subworkflows/`.

---

## 1. Drug discovery

**API:** `webapps/.../drug_discovery.py:16` is a thin mounter re-exporting the router from `ai/drug_discovery/api_router.py:51` (`APIRouter(prefix="/api/drug-discovery")`), auto-discovered by Galaxy. ~40 endpoints keyed by `{campaign_id}`: assay ingest, compounds, CRO export, model register/run, propose, virtual-library, retrain, ind-assembly, pk-summary, audit, campaigns, esig.

Submodules (`ai/drug_discovery/`, ~55 py files):
- **GP-Pareto optimizer** — `bayesian_optimizer.py:76` fits per-objective `GaussianProcessRegressor`, computes the Pareto front (`_compute_pareto_front` L175), acquires via hypervolume improvement (L207) + Tanimoto diversity penalty (L256), and `propose_next_round` (L323). This is the real "GP-Pareto".
- **CRO / assay / model infra** — `cro_order_export.py`, `commercial_availability.py`, `assay_ingestion.py`, `applicability_domain.py`, `custom_model_registry.py`, `auto_retrain.py` (surrogate retrain), `model_validation.py`.

**Workflows** (`subworkflows/drug_discovery/`, 53 populated `main.nf`): `openfe_rbfe/` (alchemical RBFE ΔΔG, OpenFE), `schrodinger_glide_docking/`, `moe_covalent_docking/`, `structure_prediction_docking/`, `drugclip_virtual_screening/`, `reinvent4_lead_design/` (REINVENT4 RL generator), `pharmacophore_filtering/`, `pocket_detection_druggability/`, `fpsim2_chemical_similarity/`, `scaffold_hopping/`, `aizynthfinder_retrosynthesis/`, `syncraft_synthesizability/`, `cro_submission_export/`. (Two dirs referenced elsewhere — `cohort_metadata_qc/` and `gromacs_umbrella_pmf/` — hold only an `assets/` or `work/` subdir with no `main.nf`.)

> The "~215 tested drug-dev workflows" figure spans drug_discovery + pharmacology + related domains + campaign-level model/optimizer machinery — not one folder.

### ADMET / hERG auto-loop
The prediction workflow is filed under **`subworkflows/pharmacology/predict_admet_properties/main.nf`** (there is **no** `drug_discovery/predict_admet_properties/` dir — it does not exist under `drug_discovery/`). It emits `toxicity_report.json` / `qc_metrics.json`. The QC gate is enforced in `nextflow_executor.py:_evaluate_qc_from_s3` (L3179): the ADMET path triggers on `toxicity_report.json` (L3195), surfaces `herg_ic50_uM` / `dili_risk` / `dili_probability` (L3340) as **halt-vs-advisory** gate failures. Remediation is served at `GET /api/invocations/{id}/autoloop-suggestions` (L7271); SSE `autoloop_gate_results`/`autoloop_update` inject around L3294. Full gate/remediation mechanics: [WORKFLOW_EXECUTION §3](../03-backend-ai/WORKFLOW_EXECUTION.md).

## 2. PBPK

`subworkflows/drug_discovery/pbpk_simulation/main.nf` — an **8-compartment Rodgers/Rowland mechanistic PBPK** model as a SciPy ODE system (gut/liver/blood/lung/kidney/peripheral) with population scaling (`healthy_adult | child | elderly | hepatic_impairment`). Process `PBPK_SIMULATION` (L46) emits `pk_profile.csv`, `nca_parameters.json`, `ddi_fold_change.json`, `qc_metrics.json`.

Canonical params (declared in the `.nf`, L26–45): `SMILES`, `MW`, `logP`, `pKa`, `fu_plasma`, `fu_mic`, `CLint_uL_min_mg`, `renal_CL_mL_min`, `OATP1B1_substrate`, `Pgp_substrate`, `population`, `dose_mg`, `dose_route`, `simulation_hours`, optional `auc_observed_ug_h_mL` (feeds the `pbpk_auc_fold_error` gate, FDA 2018). **There is no hardcoded PBPK alias table** — PBPK prefill uses the generic hybrid rule+LLM extractor. Variants: `pbpk_pediatric/`, `pbpk_peripheral_nerve/`, `pk_sim_pbpk/`, `simcyp_pbpk/`.

## 3. IND / regulatory / CRO

- **IND assembly** — `ai/drug_discovery/ind_assembly.py` (~3.9k lines). `INDSectionAssembler.assemble()` (L1068) generates ICH M4 CTD §2.4 + §2.6.1–2.6.3; §2.6.1 subsections: overview (L1611), PBPK (L1699), ADMET (L1777), prioritization (L1867), applicability domain (L1915). `_llm_narrative()` (L692) resolves an LLM backend (Frontier → Modal → vLLM → local Qwen3-8B LoRA), injects pre-computed MRSD numbers (L716), applies `_regulatory_guardrails()` (L512, citation injection + numeric faithfulness), builds RAG context (L915). DOCX via pandoc.
- **Router** — `webapps/.../ind_actions.py` → `ind_actions_router.py`. `sign_document()` (L131) is 21 CFR Part 11 two-factor e-sign (JWT + TOTP). Also `POST /{campaign_id}/ind-assembly` (`api_router.py:1121`). Auto-loop `ind_autoloop.py:32` regenerates ≤3× against a quick audit (PBPK/genotox/cardiac citation checks).
- **CRO** — `cro_order_export.py` `CROOrderExporter` (WuXi/Pharmaron/Enamine CSV), `commercial_availability.py`; workflow `cro_submission_export/main.nf` (VALIDATE_COMPOUNDS hERG gate → FORMAT → EXPORT_CSV); `GET /api/drug-discovery/{campaign_id}/export/cro-order`.
- **`ai/compliance/`** — `audit_middleware.py` (records EXPORT_CRO_ORDER / PROPOSE_ROUND / ASSEMBLE_IND), `audit_store.py` (SHA-256 hash-chained append-only SQLite, `verify_chain()`), `esig.py` (TOTP RFC 6238 + AES-256-GCM per 21 CFR 11 §11.50/§11.200).
- **Regulatory knowledge** — `regulatory_auditor.py` two-tier (Tier-1 regex, Tier-2 LLM semantic judge). `regulatory_knowledge.yaml` = versioned guideline registry (ICH M4S/S7A/S7B/S2(R1)/M3(R2)/E5, FDA PBPK 2018, EMA 67%-within-2-fold, NMPA/PMDA, 21 CFR 11, FDA/EMA AI guidance Jan 2026). `phase_gating.py:53` maps ICH M3(R2) Table 1 → genotox/hERG/DART/carcinogenicity battery. `mrsd_calculator.py:47` does deterministic NOAEL→HED→MRSD (replacing LLM arithmetic).

## 4. Cryo-EM

- **Knowledge package** — `ai/cryo_em_knowledge/` (a package, not a single `.py`): `schema.py` (SQLite `cryo_em_protocols`/`parameters`/`tools` + FTS5 + RAG vec), `populate.py` (6 sample classes: saposin_nanodisc, msp_nanodisc_gpcr, detergent_ion_channel, liposome_pore_forming, rna_protein_endogenous, symmetric_assembly; 68 MW-binned params; 20+ tools with have/partial/missing status), `retriever.py` (`CryoEMKnowledgeRetriever`: `get_protocol`, `get_parameters_for_mw`, `detect_sample_class` keyword+BGE-centroid, `semantic_search`, `get_full_context`), `rag_index.py` (embeds `docs/cryo_em_skills/*.md` → sqlite-vec). API: `webapps/.../cryo_em_knowledge.py` (`/api/cryo_em/context|parameter|protocol|rag/*`).
- **Integration** — `ai_assistant.py:_add_cryo_em_guidance` (L6517) injects protocol principles/QC-gates/tool-reqs into prompts; domain-centroid intent classification uses the BGE model (L6439). Fast-path `_try_fast_path_cryosparc_spa` (L3518). `cryoem_chain_templates.py` defines 3 chains (standard_refinement 5-step, 3DVA, model_building).
- **Workflows** — `subworkflows/cryo_em/` (15: `cryosparc_standard_spa`, `helical_spa_pipeline`, `3d_variability_pipeline`, `focused_refinement_pipeline`, `local_refinement`, `global_ctf_refinement`, `symmetry_expansion`, `topaz_train`/`extract`, `particle_subtraction`, `filament_tracer`); `subworkflows/cryo_et/` (5: `et_full_pipeline`, tilt import/align, tomogram_reconstruction, subtomogram_averaging). Execution path: [WORKFLOW_EXECUTION §5](../03-backend-ai/WORKFLOW_EXECUTION.md). (The "CryoDynamics"/SNAT2 conformational work lives in `research/snat2_state_call/` and is **not** a productized module.)

## 5. Multi-omics

`ai/multiomics/`: `method_selector.py` (`select_method` L166, `recommend` L275) picks by data shape — **MOFA2** (default for paired continuous), **SNF** (clustering/subtypes), plus MCIA/iClusterPlus/JIVE/intNMF/MFA/StabMap. `integration_planner.py:METHOD_WORKFLOW` maps method → `bioconductor/mofa2/main.nf`, `bioconductor/snf_multiomics/main.nf` (a two-step normalize→integrate pipeline). `routing.py:120` builds the chat GA card. **Universal CSV interface:** each modality is a features×samples CSV; `omics_normalize` emits `normalized_<view>.csv`.

**Alignment-QC direction:** `sample_alignment()` (L119) computes paired/partial/disjoint overlap + mosaic warnings, but the "over-correction / did-I-erase-biology" gate is **not yet in this module**. The live over-correction gate is the preprocessing path in `nextflow_executor.py:_evaluate_qc_from_s3` (L3210–3249, `qc_report.json`, biology-erasure=halt else advisory) — consistent with the project note that alignment-QC is still a direction, not a shipped multiomics feature.

## 6. ML training

`ai/ml_training/`: `config.py` `TrainingConfig` (`to_workflow_ga` L278); `routing.py` rule-first intent→config (feature-flagged); `training_job.py` `run_training_job` (L118: load→train→QC-gate→MLflow→registry); `chemprop_trainer.py` dispatcher. **Models:** `chemprop_gnn` (MPNN, GPU), `ludwig_tabular` (NN + RDKit 2D), `sklearn_gbr` baseline, `ludwig_llm` (LoRA/QLoRA SFT via `llm_trainer.py`), `trl_dpo`/`trl_grpo` (preference/RL via `trl_trainer.py`). `datasets.py` (TDC/local/S3), `executor_payload.py` `build_execute_request` (→ `chemprop_train.nf`), `mlflow_tracker.py`.

**Regulatory-LLM link:** `drug_discovery/regulatory_training_jobs.py` (per-org adapter queue, 3 modes: `prompt_rules` default / `few_shot_index` / `post_train_lora` gated) + `regulatory_training_worker.py` + `auto_retrain.py`. ML training is the generic substrate the regulatory module consumes for org-specific LoRA/DPO.

## 7. Research agent & knowledge

- **Entry:** `POST /api/ai_assistant/research_query` → `answer_research_query` (`webapps/.../ai_assistant.py:5002`) → `ResearchAgent.answer_question` (`agents/research_agent.py:1256`): analyze → gather evidence (federated decomposed lit search across PubMed/arXiv/Semantic Scholar via `agents/literature_clients.py`, PMC OA full-text) → `_synthesize_response` (L2122). **Anti-confab guard** (L2456–2488): retrieved papers are numbered `[N]` and injected with an explicit "cite ONLY from this list, never invent DOI/PMID/PDB" **in-context** constraint (not a post-filter) — preserving the 0-mismatched-citations property.
- **`ai/chain_composer/`** — `composer.py:compose_chain` (L202): pattern retrieval + NER + curated exemplars + confidence scoring + LLM compose + `verifier.py` DAG validation (L349). Plus `domain_reclassifier.py`, `catalog_audit.py`.
- **`ai/retrievers/`** — `family_dedup.py`, `canonical_resolver.py`, `knowledge_recall.py`, `workflow_intent.py`, `wired_agentic_memory.py`, `qc_gate_reader.py` (largest).
- **`ai/knowledge/`** — `rare_disease.py` (HPO-overlap gene ranking), `crispr_screens.py`, `variant_enrichment.py` (GWAS enrichment).
- **`ai/pilot_analysis/`** — plugin manager + per-domain plugins (genomics/single-cell/cryo-EM/bioimaging/pharmacology) for fast feasibility/QC without full runs.
- **`ai/spectral_libraries/`** — `library_manager.py` discovers/validates DIA-NN proteomics libraries against `library_registry.json`. **Known limitation:** DIA-NN does not run on ARM64 (`spectral_libraries/ARM64_DIANN_LIMITATION.md`).

## 8. Workflow catalog structure

`subworkflows/` has **34 domain subdirectories**; `.nf` counts (bioconductor counted by `main.nf`):

| Domain | files | Domain | files | Domain | files |
|--------|------:|--------|------:|--------|------:|
| bioconductor | 1829 | single_cell | 13 | database | 6 |
| drug_discovery | 53 | bioengineering | 13 | cryo_et | 5 |
| pharmacology | 49 | virtual_cell | 12 | cell_biology | 5 |
| genomics | 37 | systems_biology | 12 | proteomics | 4 |
| molecular_biology | 26 | genetics | 11 | literature | 4 |
| bioimaging | 22 | synthetic_biology | 10 | biostatistics | 4 |
| microbiology | 16 | biochemistry | 9 | structural_biology | 3 |
| immunology | 15 | pathology | 7 | glycoengineering | 3 |
| cryo_em | 15 | lab_automation | 7 | epigenomics | 3 |
| physiology | 14 | cancer_biology | 7 | transcriptomics / multi_omics / biophysics | 2 each |
| | | | | rare_disease / molecular_dynamics | 1 each |

The **283-workflow domain catalog** referenced in routing = the sum of all non-bioconductor domains (≈283 curated domain subworkflows). Bioconductor (1,829) is the separate R utility corpus. These `subworkflows/` filenames were the ones buried by the −8 component penalty until PR #188 (see [AI_ASSISTANT §3.3](../03-backend-ai/AI_ASSISTANT.md)).

## 9. Expert-skills persona layer

A user-facing capability that shapes every response: **domain-expert personas auto-selected per query** and composed into the LLM system prompt.

- **Skill store:** `backend/lib/galaxy/ai/skills/` — 9 persona markdown files: `clinical-biostatistician`, `drug-discovery-chemist`, `gwas-statistician`, `ml-bioinformatics`, `multiomics-integrator`, `regulatory-affairs`, `rnaseq-analyst`, `single-cell-analyst`, `structural-biologist`. Each has YAML frontmatter (`triggers`, `domain`) + a system-prompt body.
- **Manager:** `ai/skill_manager.py` — `Skill` (frontmatter parse, pre-compiled `triggers` regex, `matches_query` L81, `matches_domain` L86, `system_block` L101 → the prompt fragment). Auto-detected from query triggers when not explicitly set; also a `BiocSkill` variant that turns Bioconductor package names into triggers.
- **API:** `webapps/.../ai_assistant.py` — `GET /api/skills` (L6079, list), `POST /api/skills/detect` (L6115, which persona a query triggers), `POST /api/skills/upload` (L6142, write a new skill + hot-reload), `POST /api/skills/block` (L6253). Test coverage: [TEST_PLAN §2](../09-testing/TEST_PLAN.md).

## Corrections to prior notes
1. ADMET workflow is under **`pharmacology/`**, not `drug_discovery/`.
2. **No** hardcoded PBPK alias table — generic hybrid extractor.
3. The live over-correction/alignment QC gate is in `nextflow_executor.py`, **not** `ai/multiomics/`.
4. `cryo_em_knowledge` is a **package**, not a single `.py`.
