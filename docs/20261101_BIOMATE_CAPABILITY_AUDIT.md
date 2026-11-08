# BioMate capability audit against the BD claims (2026-11-01)

**Purpose.** The BD supplement (target identification, multi-agent evidence search, multi-omics, related
directions) makes capability claims. This audit checks each claim against code, tests, the workflow
database and dated records, so that the sales team states only what is true. **Gaps are recorded
separately** in `docs/20261101_BIOMATE_GAP_REGISTER_AND_TEST_PLAN.md`.

**Method.** Four read-only audits (target identification and search; multi-omics and instrument data;
drug-development directions; platform, on-premises and governance). No product code was edited and no
paid or external call was made. Each audit used the same evidence ladder:

| Level | Meaning |
|---|---|
| L1 | Code or workflow exists |
| L2 | Wired into the live user path |
| L3 | Covered by a test |
| L4 | Verified by a real run or deployment with a dated record |

Verdicts: **VERIFIED** (L4), **BUILT** (L1 to L3), **PARTIAL**, **MISSING**, **CONTRADICTED** (the
evidence says the claim as worded is wrong), **UNVERIFIABLE**.

**What was independently re-checked by the author of this document** (against the database, 2026-11-01):
4,223 workflows and 42 domain tags; `real_exec_status` ok 701 and ok_warnings 402 (1,103 together); of
those, 407 carry `real_exec_provisional = 1` and 696 do not; the latest `real_exec_at` is 2026-10-15;
nf-core rnaseq, sarek, scrnaseq, atacseq and spatialvi have no execution status; `mofa2` and
`mofa2_mefisto` are `fixture_failed`; `mixomics`, `mixomics_spls_regression` and
`mixomics_splsda_classification` are `ok` or `ok_warnings`. Everything else below is reported by the
audits with the evidence they cite, and was not re-run here.

**Branch caveat.** The audited branch is `cursor/tutorial-live-recording-and-report-editing-4ea7`. The
on-premises stack (compose file, installer, local executors, local-LLM provider switch) exists only on
`origin/integration/next-phase` and is marked (NP). Eight files under `backend/lib/galaxy/ai/drug_discovery/`
are uncommitted in this worktree; several drug-development verdicts depend on them.

---

## 1. Target identification and evidence search

| ID | Capability | Verdict | Evidence (level) |
|---|---|---|---|
| A1 | Four-source parallel literature search with grounded citations | BUILT; fan-out verified live | `agents/literature_clients.py:620-626` (`asyncio.gather`); `research_agent.py` (no invented DOI/PMID rule); `grounded-research-reply.ts` falls back to the backend answer if markers or references are invalid; test `test_research_citation_grounding.py` (1 passed); one live pass on dev 2026-10-29. The system drops or falls back; it does **not** refuse |
| A2 | Parallel channels, arbiter, tiers, conflict flag, API and connector | PARTIAL | API `target_id_api.py`; live route builds Open Targets, table and LLM channels. STRING and pathway channels exist (`network_channels.py`) but are **not** in `default_channels()`, so they are not reachable from the route or chat tool. Default is Open Targets-primary (`orchestrator.py`, `arbiter.py`). Live run 2026-10-29 with `use_llm:false`. Six target-ID unit tests pass offline |
| A3 | Source coverage | CONTRADICTED on the count | Registry (`data_sources.py`): 58 sources, 54 live, 3 planned, 1 needs a key. Chat reaches the federated sources (about 20) through the research agent; there is no `query_database` tool. Earlier notes said "60+" |
| A4 | Client data as an evidence channel | PARTIAL (mechanism only) | `TableChannel` reads a `target,score` file given as a **server path**; chat tool does not pass `tables`; no upload path, no per-user scoping; no converter from analysis outputs to scores; no caller outside `target_id/` |
| A5 | Nominate-then-validate | BUILT, not wired | `validation.py` and one mocked test; not called from the route, chat tool or UI; the recorded live melanoma runs are identify-only |
| A6 | Drug-type (modality) guidance | MISSING | Only a requirement in `docs/20261025_REQUIREMENT_TARGETID_FOR_CLAUDE_DESIGN.md`; no code. The catalogue's `modality_triage` is a CAR-T, ADC or bispecific triage from expression data, a different function |
| A7 | LLM channel with a hospital open model | PARTIAL | Provider switches exist (`config.py`, `llm_client.py`); channel on by default; measured only with a frontier model; with a disease ID the ranking is Open Targets-primary, so the LLM weight does not change the live ranking |
| A8 | Restricted-network operation | PARTIAL | Hosts are hard-coded (Open Targets, STRING, literature hosts). Channels fail soft and report `channel_errors`, so a failure is visible. No local mirror; the route returns 400 if no channel is available; no restricted-network test |
| A9 | Novel-target performance | Established as a limit | `docs/20261025_TARGETID_LLM_CHANNEL_CONTRIBUTION.md`: advantage largely recall (0.76 famous vs 0.56 less-published, genetics 0.41); temporal holdout not tractable; no post-cutoff gold exists |
| A10 | "Multi-agent" = one coordinator over parallel channels | BUILT, as described | `orchestrator.py` fan-out via `map_reduce`; the pattern router and multi-agent orchestrator are flag-gated and dormant |
| A11 | Every statement carries a source link | CONTRADICTED | Output has rank, score, tier, fired channels and channel-level provenance; no per-target URLs or PMIDs; LLM-channel scores carry no references; no target-ID renderer in `frontend/client/src` |

Also noted: target identification **is** now a chat tool (live 2026-10-29); the final chat text of that run
said the tool had not executed although the tool event fired, so the chat summary needs review before a
demo; the connector manifest does not list the target-identification tool (manifest drift).

## 2. Multi-omics and instrument data

| ID | Capability | Verdict | Evidence |
|---|---|---|---|
| B1 | 4,223 workflows; 42 domains; "1,092 clean" | PARTIAL | Total and domains confirmed. Observed-clean is **696**; 1,103 including **407 provisional** ("assumed, not observed"). 1,879 workflows have never been tested. Only 11 of the 1,103 have a date on or after 5 Oct 2026 |
| B2 | Integration methods exist and run | PARTIAL | mixOmics (three workflows) is the only clean integration method in the catalogue. `mofa2`, `mofa2_mefisto`, `classifyr_multi_view_integration`, BANKSY: `fixture_failed`; multiWGCNA: `exec_error`; Harmony and scVI: never tested. The 2026-07-29 roadmap records MOFA2, SNF, intNMF, MCIA, iClusterPlus and JIVE running on Batch for three cohorts, which conflicts with the database flags |
| B3 | Per-layer analyses verified | PARTIAL, varies by layer | Workflows / ok / ok non-provisional (name-based, approximate): bulk DE 32/16/12; enrichment 34/16/13; somatic variant 14/**0**/0; CNV 34/5/5; scRNA 117/37/25; spatial 45/9/6; ATAC 13/4/2; ChIP 19/5/3; methylation 70/17/14; proteomics 24/6/4; metabolomics 25/2/1; TCR/BCR 8/2/2; survival 16/3/**0**. Nuclei segmentation: one `ok` workflow. nf-core flagships (rnaseq, sarek, atacseq, scrnaseq, methylseq, diaproteomics, spatialvi) are untested: 229 of 230 nf-core rows have no status, one is `exec_error` |
| B4 | Instrument-data workflows verified | PARTIAL | Flow 34/11/8; CyTOF/IMC 12/6/3; mass spec 18/6/3; NMR 4/**0**/0; qPCR 26/10/**0**; ELISA and plate reader: none found; cryo-EM 19, **none tested** (needs an external CryoSPARC GPU host; the 2026-07-30 test did not complete); Cell Painting 7/0/0; ITC 1/0 |
| B5 | Omics results feed target identification | MISSING | `TableChannel` reads a user-supplied score file; no code converts a run's output (DE, survival, markers, dependency) into channel scores |
| B6 | Held-out validation, confound and QC gates in multi-omics | PARTIAL, mostly MISSING | Planner has a sample-overlap check only. QC gates exist for hts, clinical_trial, allometric, ivive, openfe, pocket_detection, aizynthfinder, structure_prediction, cancer_biology, cryo_em, ADMET; **none** for RNA-seq, variant calling or integration. Confound and hold-out logic is in `ml_training` and research code, not in the omics product path |
| B7 | Runs on the client's compute | PARTIAL | Profile defaults to Docker unless AWS is enabled. This branch has only AWS Batch and Slurm; (NP) adds local, Slurm, k8s and Batch. AWS dependencies: S3, ECR (2,782 of 4,223 database image references point at one AWS account), Batch. The only on-prem test (2026-09-26, single EC2 node) ran a trivial ADMET workflow in about 10 s |
| B8 | Every result records inputs, parameters, method, version | PARTIAL | `execution_runs` stores workflow definition, input bindings, parameters, steps, metrics, output directory. No container digest capture found; QC events not durably persisted (a sidecar fix is documented, deployment unconfirmed) |
| B9 | Verified at hospital scale | MISSING | No cohort-scale run recorded; WGS and cryo-EM UI tests did not complete; verified runs are mostly default or example data |

## 3. Drug-development directions

Caveat for this whole section: `real_exec_status` is empty for essentially every drug-discovery and
pharmacology workflow. Run evidence is in dated documents, not the database.

| ID | Capability | Verdict | Evidence |
|---|---|---|---|
| C1 | Choose small molecule, peptide or antibody | CONTRADICTED as worded | `modality_triage` is a CAR-T, ADC, bispecific triage; `glp1_modality_bakeoff` is GLP-1 specific; no three-way selector |
| C2 | Design small molecules, peptides, antibodies | PARTIAL | Workflows exist (REINVENT4, scaffold hopping, cyclic-peptide design, scFv and bispecific design); none has a recorded real execution. No humanisation or CDR-graft tool. Cyclic-peptide pick accuracy about equals random on the pilot (57.7% default vs 59.6% random on 104 post-cutoff complexes); cross-target generalisation null |
| C3 | Docking, structure, binding energy, ADMET, developability | PARTIAL | ADMET hERG gate fired live once (run `d0ff684b`, 2026-10-04; the same run gave aspirin a "high" DILI score, which looks wrong); a later run produced no gates because a profile override applied. Docking validation (April) failed: RMSD 3.18 Å against a 2.0 Å target; no re-run found. Permeability is ranking-grade (R² about 0.45). Vina, DiffDock, Boltz, MM-GBSA workflows untested |
| C4 | Novelty and freedom-to-operate check | PARTIAL | Research script (`drug_novelty_fto.py`) with tests; 22 cyclic peptides screened (2 occupied, 20 novel). Not wired into the product; patent axis weak for peptides; sequence axis never ran; gate is fail-open; legal FTO still required |
| C5 | BOIN, PK/PBPK, NCA, exposure-response | PARTIAL | Workflows exist; none has a database execution record. A 2026-05-27 sweep ran the trial simulator. PBPK same-item Cmax within 2-fold: 3/15 (0.20) then 8/15 (0.53) after a fix, a local run, dev rerun pending, below the 0.60 target. The "100%" BOIN figure measures intent routing, not dose-escalation accuracy. PKNCA never executed through the product |
| C6 | First-in-human dose check for biologics | PARTIAL | `biologics_mabel.py` is a text checker with no caller. A NOAEL-based small-molecule calculator is wired into IND assembly, which is hidden |
| C7 | Safety and translational evidence package | PARTIAL | Report ingesters exist; the October failures (species, dropped values, predicted stored as measured) are fixed in the uncommitted working tree only; PDF extraction never tested on a real report; no evidence-gap listing found |
| C8 | Learning from experiments | BUILT (uncommitted; synthetic) | `/ingest-assay` to refit to `/propose`; unit, identity, censoring and salt checks pass in the 2026-10-31 log; assay source simulated; refits are **not** routed through the model registry or compared with the previous version on a holdout before adoption |
| C9 | Fine-tune on hospital data with versions and lineage | PARTIAL | Model registry committed and tested (immutable versions, gated promotion with a named reviewer, rollback, compare). Fine-tune launch is off on dev (`ML_TRAINING_ROUTING`), no UI launch, no lineage round-trip, GPU path not wired |
| C10 | T-cell and immune research | PARTIAL, catalogue only | scRepertoire BCR clustering is the only run record; HLA typing and epitope prediction never run; tumour-reactive T-cell identification not found |
| C11 | Organoid and drug-sensitivity analysis | PARTIAL | SynergyFinder (3 workflows) verified 2026-06-09; plate QC and dose-response workflows never run; no omics link |
| C12 | Drug repurposing | PARTIAL, catalogue only | Workflows exist, none run; no quality benchmark |
| C13 | Survival, stratification, biomarker panels | PARTIAL | Three `kmcut` Cox workflows verified (2026-06-09). `survival_analysis_km` simulates from parameters rather than analysing patient data; `biomarker_patient_enrichment` is a stub; no held-out validation in a verified workflow |

## 4. Platform, on-premises and governance

| ID | Capability | Verdict | Evidence |
|---|---|---|---|
| D1 | Installable on the hospital's infrastructure | PARTIAL | (NP) compose file, installer, update script, Chinese-language setup guide; one dated simulated install (2026-09-26, cloud VM with internet and a cloud LLM, 9 of 9 journey steps, 26 install bugs found and fixed, pull request still open). Not tested on a clean or air-gapped host |
| D2 | Independent of AWS | PARTIAL | (NP) executor switch local, Slurm, k8s, Batch; MinIO and a local registry replace S3 and ECR. About 150 backend files reference AWS libraries; hard-coded ECR image paths; executor variables not in the example env file |
| D3 | Model-agnostic, no external provider calls | PARTIAL | Two on-prem model paths exist (an OpenAI-compatible provider switch (NP), and a local-only mode on this branch). Defaults are cloud (Anthropic, then Gemini fallback); the OpenAI-compatible path has no guard against the cloud cascade. On-prem measured evidence is narrow: a 27B model passed 12 of 12 synthetic tasks ("not client-ready"); routing-only results with a 9B model |
| D4 | No phone-home | CONTRADICTED by default | The web client loads a Google tag and Google Fonts unconditionally; analytics code posts to Google Analytics when a secret is set. Required outbound traffic for internal use is only the model endpoint. Optional: literature and database APIs, tool shed, catalogue download. Removable: analytics, fonts, CDNs |
| D5 | Known external domains; offline mode | PARTIAL | About 120 call sites recorded in earlier air-gap documents; no vetted allow-list; no mirror or offline mode (the offline flag only hides the literature and target tools) |
| D6 | Provenance and audit | PARTIAL | `reproducibility-record.ts` assembles a record per run (output hashes reserved for later); a hash-chained audit store exists but is wired only from drug-discovery code; QC events not durably persisted; audit cold tier depends on AWS |
| D7 | Governance and multi-team use | PARTIAL | Project-level viewer and editor roles; no LDAP, SAML or OIDC; no organisation or team entity; no reviewer UI for the access log |
| D8 | Patient-data protection | PARTIAL | Six regular-expression patterns strip identifiers from chat text; field-level encryption for selected columns; `phi-classification.ts` is not imported anywhere; no dataset de-identification; encryption falls back to a hard-coded development secret if unset; no retention or deletion policy |
| D9 | Integration with hospital systems | PARTIAL / MISSING | Benchling connector (uncommitted); MCP and API connectors; no HIS, LIS, FHIR, DICOM, REDCap or OMOP connector; no institutional SSO |
| D10 | Data ownership and no tenant sharing | PARTIAL | Memory and knowledge are scoped by user or project in application code; no row-level security; cache-key isolation not audited; nothing found showing user data entering shared training, but no test or policy asserts it |

---

## 4b. Multi-modal clinical data (added 2026-11-01)

Added after the BD team asked how and where the client's multi-modal clinical data would be used.
Catalogue queries run by the author on 2026-11-01 (name and description keyword matches, so
approximate): total matches, matches with `real_exec_status` ok or ok_warnings, and of those the
non-provisional ones.

| Modality or capability | Matches / ok / ok non-provisional | Verdict | Notes |
|---|---|---|---|
| Radiology (radiomics, DICOM, CT, MRI, PET) | 2 / 0 / 0 | MISSING | No named radiomics workflow. A pilot-analysis plugin (`pilot_analysis/plugins/bioimaging.py`) uses pydicom and nibabel for quick image characterisation only. The 2026-09-08 hospital-needs audit rated radiology PARTIAL |
| Pathology slides and histology | 10 / 3 / 3 | PARTIAL | One nuclei-segmentation workflow `ok`. The 2026-09-08 audit: slide-level diagnostic AI is a specialist-vendor area, a gap by design; BioMate is the research-analysis layer |
| Survival analysis | 37 / 3 / 1 | PARTIAL | Cox workflows (kmcut) verified 2026-06-09; the Kaplan-Meier workflow simulates from parameters; see gaps K3, M4, R12 |
| Electronic records (EHR, FHIR, OMOP, REDCap) | 2 / 0 / 0 | MISSING | No connector to hospital information, image archive or laboratory systems (audit item D9) |
| Circulating DNA and liquid biopsy | 2 / 0 / 0 | UNVERIFIED | Listed, never run |
| "Multimodal" workflows | 6 / 0 / 0 | UNVERIFIED | None executed |
| Multi-omics integration methods | 32 / 5 / 5 | PARTIAL | mixOmics verified; MOFA2 and others see section 2 (B2) |
| Patient stratification research | n/a | Reference | `docs/20260817_PATIENT_STRATIFICATION_SURVEY.md` surveys the approaches and records the main failure mode: leakage, no external validation, no calibration |

What this means for the BD answer: the molecular, pathology and clinical-cohort analyses can be run and
matched by patient in a project; there is no verified radiology analysis, no hospital-system connector
and no automated integration gate, so data arrive as exported tables and images and the integration
checks are part of the protocol. Gaps K1 to K6 in the register track the work.

---

## 5. What is genuinely solid (verified at L4 or well covered)

- The four-source parallel literature search with a grounding guard (one dated live pass on dev, 2026-10-29).
- The Open Targets query path and the target-identification service reaching the chat tool (live run 2026-10-29, `use_llm:false`).
- A catalogue of 4,223 indexed workflows, 696 of them observed-clean, including mixOmics integration, edgeR and limma differential expression, enrichment, scRNA quality control, methylation, survival (kmcut Cox), flow and mass cytometry, SynergyFinder and nuclei segmentation.
- The model registry with gated promotion and rollback (committed and tested).
- One live ADMET hERG gate firing with automatic remediation (2026-10-04).
- The honest measurement record: memorisation control on the language-model channel, the 17-cancer comparison with Open Targets, the PBPK scores, the docking failure.
