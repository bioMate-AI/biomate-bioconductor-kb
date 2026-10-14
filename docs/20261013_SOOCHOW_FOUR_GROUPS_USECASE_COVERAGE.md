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
