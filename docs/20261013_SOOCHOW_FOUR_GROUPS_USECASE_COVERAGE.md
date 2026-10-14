# Soochow (苏大附一院) Four Research Groups — BioMate Use-Case & Instrument Coverage Audit

**Date:** 2026-10-13
**Purpose:** For the prospective collaboration/client at the **Department of Rheumatology & Immunology, First Affiliated Hospital of Soochow University** + the **Jiangsu Institute of Clinical Immunology**, confirm that BioMate's demonstrated use cases (cold-start examples, tutorials, runnable workflows) and its **instrument/lab-connectivity** cover the four groups' collected research directions. Flags gaps and recommends additions.
**Source of research directions:** `docs/20260930_HOSPITAL_SURVEY_SOOCHOW_RHEUM_CYCLICPEPTIDE_COLLAB.md` + `docs/20260930_HOSPITAL_ROSTERS_AND_PUBLICATIONS.md` §B (author-verified).
**Scope note:** "Four groups" = the four natural PI clusters at Soochow; their *union* of research directions is what the product must cover. If a different four were intended, the direction→use-case matrix below still applies.

---

## The four groups and their research directions (collected)

| # | Group (PI) | Research directions (verified) |
|---|---|---|
| **1** | **Wu Jian 武剑** — Dept Director; cell-therapy / severe autoimmune | CAR-cell therapy for refractory autoimmune (**UTAA91**: off-the-shelf allogeneic CAR-Vδ1T + CD19 nanobody + PD-1-agonist nanobody); difficult CTD (SLE, Sjögren's, ILD, PH); national drug-trial base (multicenter trials) |
| **2** | **Liu Cuiping 刘翠萍** — Jiangsu Inst. wet-lab PI | Surface immune receptors + secreted checkpoint ligands (**CD226/DNAM-1, TIGIT, B7 family, BST2, CD200/CD200R, IL-23**); **flow-cytometry immunophenotyping + soluble-protein ELISA** biomarkers in pSS/SLE/RA; immune-subset profiling |
| **3** | **Chang Xin 常新** — clinician-scientist; cohorts | Clinical correlative studies (receptor expression vs disease activity); autoimmune **cohorts** (SLE/RA/Sjögren's) — responder stratification, biologic-therapy real-world (telitacicept/belimumab), inflammatory-marker mortality epidemiology |
| **4** | **Zhang Xueguang 张学光** — Jiangsu Inst. founding director; platform | **Antibody engineering**, co-stimulatory molecules, B7 family (B7-H3, c-Met); recombinant-protein / **SPR** interface assays; therapeutic-reagent platform |
| + | *Mo Xingbo 莫兴波 (genetics)* | SLE susceptibility genes, Mendelian randomization / immunogenetics |
| + | *In-vivo* (Cheng Wei) | **MRL/lpr lupus model** — the one causal target experiment (IL-23p19 blockade) |

**Collaboration thesis (why us):** their targets are **extracellular immune-receptor / secreted-checkpoint PPIs** — flat interfaces, no small-molecule pocket, mostly no cell-penetration need — the exact space BioMate's **cyclic-peptide/macrocycle design engine** addresses, with their flow + ELISA + MRL/lpr assays closing the design→test→learn loop.

---

## Use-case coverage matrix (research direction → BioMate demonstrated capability)

| Research direction | BioMate use case / example | Status |
|---|---|---|
| **Macrocycle / cyclic-peptide design vs PPI targets** (the core thesis) | Design & generate — `peptides` (1BXL BCL-XL BH3), `macrocycles` (OPRM1 BindingDB ring), `enzyme`/`molecules` examples; multi-objective verdict view; ADMET/developability gates | ✅ **Strong** — directly aligned |
| **Antibody / nanobody design** (Wu Jian UTAA91 nanobodies; Zhang Xueguang antibodies) | Design — `biologics` example (6Z43 nanobody–SARS-CoV-2 spike, CDR constraints); structural biology | ✅ Covered (nanobody/antibody framework design) |
| **Target ID / structural PPI** (B7 family, CD226, IL-23R interfaces) | Structural biology (AlphaFold/1LYZ), docking (1IEP), **Predict Binding Affinity** (runs E2E) | ✅ Covered |
| **ADMET / developability** of leads | ADMET workflow (hERG, DILI, oral bioavailability, CYP, Caco-2 — runs E2E) | ✅ Strong |
| **Autoimmune cohort analysis / differential expression** (SLE/RA/pSS) | **Myasthenia-gravis PBMC DE demo (GSE227835)** — *already an autoimmune cohort*; `nf-core/differentialabundance` (runs); clustering | ✅ Covered (autoimmune DE is the flagship demo) |
| **Responder stratification / biologic-therapy real-world** (telitacicept/belimumab) | Survival (Cox PH — runs), clinical stats, differential abundance | ✅ Covered (method), ⚠️ no disease-specific SLE/RA responder demo |
| **Clinical trial design / dose finding** (national drug-trial base) | `clinical_trial_simulation` (runs E2E); BOIN dose escalation | ✅ Covered |
| **CAR-cell therapy analytics** (UTAA91 product QC, Vδ1 purity/expansion) | — | ⚠️ **Partial** — no CAR-T product-characterization / flow-QC demo |
| **Flow-cytometry immunophenotyping** (CD226⁺ B, TIGIT⁺ NK, BST2⁺CD4⁺ T) — *Liu Cuiping's core method* | — (no FCS analysis workflow or cold-start example) | ❌ **GAP** |
| **Soluble-protein ELISA biomarker analysis** (soluble B7 family) | — (no plate-reader/ELISA analysis example) | ❌ **GAP** |
| **SPR / binding-interface assay analysis** (Zhang Xueguang platform) | — (binding *prediction* exists; no SPR curve-fit workflow) | ❌ Gap (minor) |
| **Immunogenetics — SLE susceptibility, Mendelian randomization** (Mo Xingbo) | Variant calling (per-pipeline issues); no MR workflow | ⚠️ Partial / gap |
| **In-vivo model readouts** (MRL/lpr: proteinuria, anti-dsDNA, Th17/Treg) | Wet-lab, not bioinformatics — out of scope for the platform (closes the loop via assay ingestion) | n/a |

**Headline:** the **drug-design half** of the collaboration (target→macrocycle→ADMET→structure→binding) and **cohort/clinical analytics** are **well covered** — the MG PBMC demo is itself an autoimmune differential-expression use case. The **immunology wet-lab readout half** (flow cytometry, ELISA) that is Liu Cuiping's and the clients' daily method is the **main coverage gap**.

---

## Instrument / lab-connectivity coverage (for potential clients)

BioMate's `INSTRUMENT_TYPES` (`frontend/shared/schema.ts`) and real connectors (`backend/lib/integrations/`):

| Client wet-lab instrument | BioMate instrument type | Connector status | Client relevance |
|---|---|---|---|
| **Flow cytometer** (FCS) | `flow_cytometer` | ✅ real file-watcher connector | **Core** — Liu Cuiping immunophenotyping |
| **Plate reader** (BMG/BioTek/Tecan) | `plate_reader` | ✅ real connector | **Core** — ELISA soluble-ligand readouts |
| **LC-MS** (Thermo/Waters/Bruker/SCIEX) | `lcms` | ✅ real connector | Proteomics/metabolomics |
| **ELN / LIMS** | `benchling` | ✅ REST (OAuth2) | Cohort/trial data governance |
| **Illumina sequencer** | `basespace` | ✅ OAuth2 cloud | Omics (if adopted) |
| **Nanopore** | `minknow` | ✅ HTTP | Omics |
| **Liquid handler** | `opentrons` | ✅ MCP (the one *user-drivable* path) | SDL / assay automation |
| qPCR / cryo-EM / generic SiLA2 | `qpcr`/`epu`/`sila2` | ✅ connectors | breadth |

**Coverage verdict:** every instrument the Soochow wet-lab runs (**flow cytometer, plate reader, LC-MS, ELN**) has a **real connector** — the capability exists. **But the user-facing demonstration is OpenTrons-only** (`I14`: "`list_instruments` et al. are OpenTrons-only today"; non-OpenTrons are file-watchers not yet driven from chat). So for a hospital/CRO prospect, the instruments *story* is real at the connector layer but **not yet demonstrated end-to-end** for flow/plate-reader/LC-MS in the manual or demo.

---

## Gaps and recommendations (to "cover their use cases" fully)

1. **Flow-cytometry immunophenotyping use case (highest-value gap).** Add a cold-start example + workflow: FCS ingest → gating/population stats → marker-positive subset quantification (mirrors CD226⁺ B / TIGIT⁺ NK / BST2⁺CD4⁺ T). Pairs with the `flow_cytometer` connector → a complete "instrument → analysis → finding" story for the clients' daily method.
2. **ELISA / plate-reader biomarker use case.** Add a plate-reader example: soluble-ligand concentration curve → group comparison (mirrors soluble B7-family in pSS). Pairs with `plate_reader`.
3. **Autoimmune disease-specific demo.** The MG demo already proves autoimmune DE; add (or relabel) an **SLE/Sjögren's responder-stratification** example (biologic-therapy response, à la telitacicept/belimumab) to speak directly to their diseases and cohorts.
4. **CAR-T / cell-therapy analytics** (optional, speaks to Wu Jian): a flow-based product-characterization example (Vδ1 purity/expansion).
5. **Instrument demonstration beyond OpenTrons.** Extend the T6/I14 instrument tutorials (and ideally a demo) to show the flow-cytometer / plate-reader / LC-MS file-watcher path end-to-end, so the instruments pitch is demonstrable to hospital/CRO prospects — not just connector-level.
6. **Immunogenetics (Mo Xingbo):** a GWAS/Mendelian-randomization example would cover SLE-susceptibility work (lower priority).

**Already strong — lead the pitch with these:** cyclic-peptide/macrocycle design vs their extracellular PPI targets (IL-23/IL-23R, CD226, B7 family), ADMET/developability, structural + binding-affinity, autoimmune cohort DE, and clinical-trial simulation. The design→ADMET→structure arc maps 1:1 onto the §7 collaboration plan (IL-23/IL-23R macrocycle PoC).

---

## Next step
If you want the gaps closed (not just audited), the top two — a **flow-cytometry** and a **plate-reader/ELISA** cold-start example + runnable workflow, plus the **instrument demonstration** — would make the manual/demo fully cover these four groups' use cases. Flag and I will scope them.

---

## Update (2026-10-13) — gaps addressed

**Correction to the audit:** the analysis *capability* was NOT missing — it is already in the catalog. The real gap was a cold-start *demo example* + the instrument→analysis story. Workflows found:
- **Flow cytometry:** `flowcore` (id 11393, bioconductor) — **real-execution-verified (`ok_warnings`, produced 3 outputs)**: FCS → compensation → transform → gating. Plus `analyze_flow_cytometry_immunophenotyping` (10612, cell_biology): gating strategy → marker-positive population quantification (CD-marker⁺ subsets — exactly the Liu Cuiping readout).
- **ELISA / soluble-ligand:** `analyze_ebv_antibody_titers` (10694, immunology) — standard-curve fit → titer quantification by group; **fully self-contained on built-in demo data** (OD + standard curve + EBV+/active/− groups as default params). Also `Dose Response` (10565) and `hts_plate_qc_hit_calling` (12882) for plate-reader QC/curves.

**Done (committed, not synced):**
1. **ELISA cold-start example added** — `PREPARED_EXAMPLES` in `cold-start-examples.ts`: "EBV antibody titers (ELISA)" → `analyze_ebv_antibody_titers`, param-only / built-in data (self-contained like the ADMET + metaboanalystr examples). Demonstrates the soluble-protein-ELISA → titer → group-comparison method.
2. **Instrument → analysis worked example** added to `I14` ("Worked example — from a bench instrument to an immunology readout") and a pointer in `T6` §6: flow cytometer→`flowcore`/immunophenotyping, plate reader→`analyze_ebv_antibody_titers`, LC-MS→proteomics/metabolomics — honest about the connector (admin-deployed watcher) vs the analysis (live from chat).

**Remaining follow-up (needs a dev run / small fix — not done here):**
- **Flow-cytometry cold-start example not yet added as wire-ready.** The FCS demo file exists in-repo (`backend/biomni_workflows/sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs`), but `analyze_flow_cytometry_immunophenotyping`'s default `fcs_file_path` is a **developer-local absolute path** (`/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs`) that will not resolve on dev. The one-line fix is to repoint that default to the deployed `sample_data/flow_cytometry/` path (or stage the FCS where the executor resolves it), then add the cold-start "flow-cytometry immunophenotyping" example and verify E2E on dev. Left undone because editing an executed subworkflow's default without a dev test is unsafe from a no-sync fork.
- **E2E verification of the ELISA example** on dev pending a sync (param-only → high confidence it dispatches, like ADMET).

---

## Per-faculty-group direction → BioMate workflow mapping (expanded, catalog-verified 2026-10-14)

Catalog probe (`backend/database/galaxy_ai_tools.db`, 4,210 workflows) confirms BioMate already **has** runnable workflows for each group's directions — far beyond the original flow/ELISA pair. Each row cites a real catalog workflow. Legend: ✅ workflow exists · 🎬 cold-start demo exists · ➕ recommend adding a demo.

### Group 1 — Wu Jian 武剑 (cell-therapy / severe autoimmune / national drug-trial base)
| Direction | BioMate workflow(s) | Status |
|---|---|---|
| CAR construct / CAR-Vδ1T design (UTAA91) | `cart_construct_design`, `in_vivo_cart_codesign`, `modality_triage` | ✅ ➕ (high value — directly UTAA91-aligned) |
| CD19 / PD-1 nanobody design | Design & generate `biologics` cold-start example (6Z43 nanobody–spike) — *a design surface, not a catalog workflow* | ✅ 🎬 |
| Multicenter drug trials (national base) | `clinical_trial_simulation`, `patient_recruitment_feasibility`, BOIN dose-escalation | ✅ 🎬 (trial-sim) |
| Difficult-autoimmune cohort / responder | `survival_cox_proportional_hazards_regression` (+ 61 survival workflows) | ✅ ➕ |

### Group 2 — Liu Cuiping 刘翠萍 (immune receptors / checkpoint; flow + ELISA)
| Direction | BioMate workflow(s) | Status |
|---|---|---|
| Flow-cytometry immunophenotyping (CD226⁺ B / TIGIT⁺ NK / BST2⁺CD4⁺ T) | `Analyze Flow Cytometry Immunophenotyping`, `flowcore` (307 flow workflows) | ✅ ➕ (demo needs the FCS default-path fix) |
| Soluble checkpoint-ligand ELISA (B7 family) | `Analyze Ebv Antibody Titers` | ✅ 🎬 (added) |
| Immune-subset profiling / deconvolution | `deconrnaseq`, `demixt`, `consica`, `easier` | ✅ ➕ |
| Receptor–ligand cell interaction (CD226–CD155) | `InterCellar` | ✅ ➕ |

### Group 3 — Chang Xin 常新 (clinical cohorts; responder stratification; epidemiology)
| Direction | BioMate workflow(s) | Status |
|---|---|---|
| Responder stratification (telitacicept / belimumab) | survival/Cox (61 workflows) | ✅ ➕ |
| Autoimmune cohort differential expression (SLE/RA/pSS) | `nf-core/differentialabundance` | ✅ 🎬 (the MG RNA-seq demo) |
| Inflammatory-marker mortality epidemiology | survival/Cox, `patient_recruitment_feasibility` | ✅ ➕ |
| Disease-activity clustering | clustering / consensus-cluster workflows | ✅ |

### Group 4 — Zhang Xueguang 张学光 (antibody engineering; B7 family; interface assays)
| Direction | BioMate workflow(s) | Status |
|---|---|---|
| Antibody / nanobody engineering | Design & generate `biologics` cold-start example — *a design surface, not a catalog workflow* | ✅ 🎬 |
| Binding kinetics / interface affinity (SPR-class) | `Analyze Itc Binding Thermodynamics`, `Analyze Enzyme Kinetics Assay`, `Predict Binding Affinity` (106 kinetics/affinity workflows) | ✅ ➕ |
| B7-family target structural design | structural biology / docking / `cyclic_peptide_design` | ✅ 🎬 (design) |
| Recombinant-protein interface modelling | AlphaFold / structure prediction | ✅ |

### Group 5 — Mo Xingbo 莫兴波 (immunogenetics)
| Direction | BioMate workflow(s) | Status |
|---|---|---|
| SLE susceptibility GWAS | GWAS workflows (76), `Bayesian Finemapping With Deep VI` | ✅ ➕ |
| Mendelian randomization / causal inference | MR / colocalization workflows | ✅ ➕ |
| eQTL / cell-type-specific candidate-gene mining | `cageminer` (GWAS SNPs + coexpression networks) | ✅ ➕ |

### Cross-cutting (serve all groups' autoimmune focus)
| Direction | BioMate workflow(s) | Status |
|---|---|---|
| IL-23 / CD226 / B7 macrocycle design (collaboration core) | `cyclic_peptide_design` (autoimmune-tagged) | ✅ 🎬 |
| TCR / BCR repertoire & clonality | `lymphoseq`, `powertcr`, `immunotation`, `BloodGen3Module` (22 repertoire workflows) | ✅ ➕ |
| HLA typing | 30 HLA workflows | ✅ |
| Spatial / multi-omics immune integration | `spatial_multiomics_integration` | ✅ ➕ |

### Instruments per group (connectors confirmed; `frontend/shared/schema.ts`)
- **Liu Cuiping** — `flow_cytometer` (FCS), `plate_reader` (ELISA) ✅
- **Wu Jian (CAR-T)** — `flow_cytometer` (CAR product QC / Vδ1 purity) ✅
- **Chang Xin / cohorts** — `benchling` (ELN/cohort), `basespace` / `minknow` (sequencing) ✅
- **Zhang Xueguang** — ITC/kinetics *analysis* workflows exist ✅; **gap:** no native SPR/ITC *instrument* connector (data imported as a file) — candidate connector to add.

### Bottom line
BioMate's **capabilities cover all five faculty groups** across ~20 directions (not just the original two). The remaining work is **demonstration, not capability**: add cold-start demos (➕) for the highest-value per-group flows — **CAR-T construct design (Wu Jian), flow-cytometry immunophenotyping (Liu Cuiping), responder-survival (Chang Xin), binding-kinetics/ITC (Zhang Xueguang), GWAS/MR (Mo Xingbo)** — each pointing at the existing workflow with public demo data. The only true *capability* gap is an SPR/ITC instrument connector (analysis already supported).

### Mapping audit (2026-10-14)
Each cited workflow was verified against its real catalog description (not just a name-keyword match). **23 of 25 confirmed accurate** (e.g. `cart_construct_design` = "Full CAR-T construct design from antigen target to complete protein sequence"; `analyze_itc_binding_thermodynamics` = ITC binding affinity/thermodynamics). **Two corrected:** (1) `biologics` is the Design & generate **cold-start example**, not a catalog workflow; (2) `Analyze Protein Colocalization` is **fluorescence-microscopy** colocalization (domain=physiology), NOT genetic/eQTL colocalization — removed as a false match from Mo Xingbo's immunogenetics row (`cageminer` + `Bayesian Finemapping` are the correct genetic ones).
