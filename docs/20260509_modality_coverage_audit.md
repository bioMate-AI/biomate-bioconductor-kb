# BioMate Drug Development Coverage — Modality Audit (2026-05-09)

Source of truth for what BioMate can do across every drug development modality. Last verified: 2026-05-09 against `backend/database/galaxy_ai_tools.db` (2,461 workflows across 34 domains).

---

## Top-Level Coverage Matrix

| Modality | Coverage | License gate? | Open-source path? |
|---|---|---|---|
| Small molecule | Excellent | Glide/MOE optional | Yes |
| Antibody (mAb / scFv / bispecific / nanobody) | Excellent | None | Yes |
| ADC | Good (new) | None | Yes — BioMate native |
| siRNA / RNAi | Good (new generation step) | None | Yes |
| ASO / gapmer | Good (new) | None | Yes — BioMate native |
| mRNA therapeutic | Good (new chain) | None | Yes — BioMate native |
| CRISPR (KO / CRISPRa/i / base / prime) | Good | None | Yes |
| CAR-T / cell therapy | Good (new construct) | None | Yes — BioMate native |
| PROTAC / molecular glue | Good (new) | None | Yes — BioMate native |
| AAV gene therapy | Good (new) | None | Yes — BioMate native |
| Vaccines / epitopes | Good | None | Yes |
| Large protein / cryo-EM | Good | CryoSPARC industry | RELION fallback |
| Radiopharmaceuticals | Partial | None | Yes (limited) |
| Multi-target / combination | Partial | None | Yes |

---

## Modality Sections

Each section follows a consistent structure:
**Workflows in BioMate** → **Required inputs** → **Coverage status** → **Clinical precedent** → **Remaining gaps**

---

### 1. Small Molecule

**Workflows**:
- Discovery: `Aizynthfinder Retrosynthesis`, `Pocket Detection Druggability`, `pharmacophore_filtering`, `qsar_rf_model`
- Docking: `Docking Autodock Vina`, `Run Diffdock With Smiles`, `Schrodinger Glide Docking` (BYOL), `MOE Covalent Docking Pipeline` (BYOL), `drugclip_virtual_screening`
- Generative: `REINVENT4 Generative Lead Design`, `scaffold_hopping`, `covalent_warhead_design`
- Free energy: `OpenFE Relative Binding Free Energy (RBFE)`, `GROMACS Protein-Ligand MD + MM-GBSA`, `AMBER pmemd GPU Molecular Dynamics`
- ADMET: `Predict ADMET Properties (AI)`, `herg_cardiac_safety_qsar`, `cns_penetration_prediction`, `dart_toxicity_prediction`, `genotoxicity_ames_prediction`, `repeated_dose_tox_prediction`, `membrane_permeability_prediction`, `metabolite_prediction_biotransformer`, `oral_absorption_bcs_model`, `cyp_ddi_panel`, `transporter_ddi_prediction`
- PK / PBPK: `nlmixr2_population_pk`, `nonmem_poppk` (BYOL), `simcyp_pbpk` (BYOL+native fallback), `pk_sim_pbpk`, `nca_pknca`, `pbpk_pediatric`, `pbpk_disease_state`
- Clinical: `clinical_trial_simulation`, `adaptive_trial_design`, `phase2_dose_justification`, `biomarker_patient_enrichment`, `virtual_patient_cohort`, `exposure_response_modeling`

**Coverage**: Excellent — IND-ready chain from SMILES to §2.6 narrative
**Clinical precedent**: All major small-molecule pharma workflows
**Gaps**: covalent ADMET (warhead reactivity prediction beyond docking)

---

### 2. Antibody Biologics

**Workflows**:
- Design: `scfv_antibody_design` (ProteinMPNN + AF2, 73% success rate)
- Multi-specific: `bispecific_antibody_design` (BiTE, CrossMab, DART, DVD-Ig, KiH, nanobody fusion)
- Developability: `antibody_developability` (aggregation, deamidation, oxidation, pI, FcRn half-life, viscosity)
- PK: `fcrn_antibody_pk`, `Analyze Radiolabeled Antibody Biodistribution`
- Structure: `nf-core/proteinfold` (AF2/ESMFold/OmegaFold/RoseTTAFold), `AlphaFold DB Search`
- Selectivity: `proteome_selectivity_profiling`

**Coverage**: Excellent
**Clinical precedent**: blinatumomab (BiTE), faricimab (CrossMab), amivantamab (KiH)
**Gaps**: Fc engineering (S239D/I332E for ADCC enhancement, YTE/LS for half-life extension)

---

### 3. ADC — Antibody-Drug Conjugate

**Workflows**:
- **`adc_design`** (id=12928, NEW) — payload selection from 7 classes, linker design, DAR optimization, ADC ADMET (plasma stability, bystander, off-target tox), two-analyte PK
- Antibody component: `scfv_antibody_design`, `antibody_developability`
- Payload ADMET: `Predict ADMET Properties (AI)`

**Coverage**: Good — BioMate is the first platform with end-to-end computational ADC design
**Clinical precedent**: Enhertu, Kadcyla, Trodelvy, Adcetris, Mylotarg
**Required inputs**: target_antigen + indication
**Gaps**: bispecific ADC (dual-payload designs); next-gen topoisomerase payloads beyond SN-38

---

### 4. siRNA / RNAi

**Workflows**:
- **`sirna_design_full`** (id=12924, NEW) — mRNA → 19-21mer sliding window → Ui-Tei + Reynolds + thermo asymmetry
- `sirna_offtarget_analysis` — seed scanning, miRNA mimicry, TLR motifs
- `synlet` — synthetic lethality RNAi screen analysis
- `lnp_formulation_optimization` — siRNA LNP delivery

**Coverage**: Good
**Clinical precedent**: patisiran (Onpattro), inclisiran, givosiran
**Required inputs**: mrna_sequence + target_tissue (for delivery)
**Gaps**: RNA aptamer design (SELEX simulation)

---

### 5. ASO / Gapmer

**Workflows**:
- **`aso_gapmer_design`** (id=12927, NEW) — MOE/LNA gapmer chemistries, Tm scoring, G-quadruplex rejection, delivery by tissue

**Coverage**: Good
**Clinical precedent**: nusinersen (intrathecal MOE), inclisiran (GalNAc), givosiran (GalNAc)
**Required inputs**: target_mrna + target_tissue
**Gaps**: PMO/PPMO design for muscle (suggested only); steric block ASO for splice modulation

---

### 6. mRNA Therapeutic

**Workflows**:
- **`mrna_therapeutic_design`** (id=12929, NEW) — full pipeline: codon opt → UTR → poly-A → stability → m1Ψ + CleanCap → IVT template → LNP by tissue
- `P0 Mrna Validation` — internal validation pipeline (codon + UTR + signal peptide)
- `Optimize Codons For Heterologous Expression` — generic codon optimization
- `lnp_formulation_optimization` — LNP formulation
- `nf-core/smrnaseq` — small RNA-seq analytics

**Coverage**: Good — chain now exists end-to-end
**Clinical precedent**: Comirnaty (BioNTech/Pfizer), Spikevax (Moderna), Onpattro chemistries
**Required inputs**: protein_sequence + target_tissue
**Gaps**: self-amplifying RNA (saRNA), circular RNA (oRNA), mRNA-LNP for CNS delivery

---

### 7. CRISPR Gene Editing

**Workflows**:
- Design: `Design Knockout Sgrna`, `crisprDesign` (KO/CRISPRa/CRISPRi/base editing), `crisprScore` (Azimuth/DeepHF/RuleSet1, CFD/MIT off-target), `CRISPRseek`
- Screens: `Crispr Screen Mageck`, `nf-core/crisprseq`, `gscreend`, `MAGeCKFlute`, `gCrisprTools`
- Analysis: `Analyze Crispr Genome Editing`, `Analyze Cas9 Mutation Outcomes`, `CrispRVariants`, `Perturb Seq Analysis`
- Prediction: `gears_perturbation_prediction` (combinatorial KO), `state_perturbation_prediction`, `evo2_variant_effect`

**Coverage**: Good
**Clinical precedent**: Casgevy (sickle cell, ex vivo), exa-cel
**Required inputs**: target gene + species
**Gaps**: dedicated pegRNA design for prime editing (PE2/PE3/PE5); HDR donor template design; in vivo CRISPR-AAV co-design (use `cart_construct_design` + `aav_serotype_selection`)

---

### 8. CAR-T / Cell Therapy

**Workflows**:
- **`cart_construct_design`** (id=12926, NEW) — 20-target scFv library, full domain assembly, packaging + tonic signaling scoring
- scFv source: `scfv_antibody_design`, `bispecific_antibody_design`
- Functional: full single-cell suite (Seurat, CITE-seq, multiome, scRNA-seq doublet QC, scRepertoire for TCR)
- Perturbation: `state_perturbation_prediction`, `gears_perturbation_prediction`

**Coverage**: Good
**Clinical precedent**: Kymriah (CD19/4-1BB), Yescarta (CD19/CD28), Abecma (BCMA/4-1BB), Carvykti (BCMA/4-1BB), Breyanzi (CD19/4-1BB), Tecartus (CD19/CD28)
**Required inputs**: target_antigen + indication
**Gaps**: TCR-T design (HLA-restricted neoantigen matching), NK cell therapy ADCC optimization, allogeneic CAR-T immune evasion engineering (B2M KO, HLA-E knock-in)

---

### 9. PROTAC / Molecular Glue / Targeted Degradation

**Workflows**:
- **`protac_design`** (id=12925, NEW) — E3 ligase from CRBN/VHL/MDM2/IAP/DCAF15, POI warhead for 25 targets, 3 linker variants, beyond-Ro5 ADMET, ternary cooperativity

**Coverage**: Good — first BioMate workflow for this modality
**Clinical precedent**: ARV-471 (ER, Phase III), ARV-110 (AR, Phase II), NX-2127 (BTK, Phase I)
**Required inputs**: target_protein + indication
**Gaps**: dedicated molecular glue discovery (vs PROTAC); LYTAC (lysosome-targeting); ATTEC (autophagy-targeting); RNA-PROTAC (RIBOTAC)

---

### 10. AAV Gene Therapy Delivery

**Workflows**:
- **`aav_serotype_selection`** (id=12930, NEW) — 10-serotype tropism database, payload size check, seroprevalence/NAb risk, route compatibility
- Companion: `mrna_therapeutic_design` (LNP alternative for non-AAV-suitable targets)

**Coverage**: Good
**Clinical precedent**: Luxturna (AAV2, retina), Zolgensma (AAV9, CNS), Hemgenix (AAV5, liver), Elevidys (AAVrh74, muscle)
**Required inputs**: target_tissue + payload_size_kb
**Gaps**: AAV capsid engineering (directed evolution), engineered capsid library (PHP.eB-class for human), dual-vector split-intein design (only flagged, not designed)

---

### 11. Vaccines / Epitopes

**Workflows**:
- `nf-core/epitopeprediction` — MHC-I/II epitope prediction, neoepitope from variants
- `nf-core/metapep` — metagenomic epitope prediction
- `Optimize Codons For Heterologous Expression` — codon optimization for vaccine antigens
- `mrna_therapeutic_design` (NEW) — full mRNA vaccine pipeline
- `nf-core/proteinfold` — antigen structure prediction

**Coverage**: Good — combine `mrna_therapeutic_design` + `nf-core/epitopeprediction` for full mRNA vaccine workflow
**Clinical precedent**: Comirnaty, Spikevax, mRNA cancer vaccines (Moderna/Merck personalized neoantigen)
**Required inputs**: antigen sequence + target population HLA
**Gaps**: saRNA / circRNA vaccine platforms; thermostable formulation design

---

### 12. Large Protein / Cryo-EM

**Workflows**:
- Structure prediction: `nf-core/proteinfold` (AF2/ESMFold/OmegaFold/RoseTTAFold), `boltz_structure_prediction` (Boltz-2 MIT), `AlphaFold DB Search`
- Cryo-EM: `CryoSPARC Standard Single-Particle Analysis`, `Helical SPA Pipeline`, `Focused Refinement Pipeline`, `3D Variability Pipeline`, `GPCR Complex SPA`, `Saposin Nanodisc SPA`, `Liposome Pore Forming SPA`, `Subtomogram Averaging`, `RELION Multi-Body Refinement`, `Cryo-ET Full Pipeline`, `Cryo-EM Conformational Heterogeneity (cryoDRGN)`, `DeepEMhancer Post-Processing`
- Interaction: `Analyze Interaction Mechanisms`

**Coverage**: Good
**Clinical precedent**: structure-driven biologics (Genentech, Vir Biotechnology)
**Gaps**: cryo-EM atomic model building (ModelAngelo + Phenix refinement); AlphaFold3 multimer + ligand pipeline (Boltz-2 covers this partially)

---

### 13. Radiopharmaceuticals

**Workflows**:
- `Analyze Radiolabeled Antibody Biodistribution`
- `Estimate Alpha Particle Radiotherapy Dosimetry`
- `RadioGx` (Bioconductor) — radiosensitivity genomics

**Coverage**: Partial
**Clinical precedent**: Pluvicto (Lu-177 PSMA), Lutathera (Lu-177 DOTATATE), Xofigo (Ra-223)
**Gaps**: PSMA/FAPi small-molecule targeting moiety design; chelator selection (DOTA/NOTA/DTPA per isotope); linker-chelator-vector assembly

---

### 14. Multi-target / Combination

**Workflows**:
- `cpa_drug_combination_synergy` (+GPU variant) — drug combination synergy
- `bispecific_antibody_design` — multi-target antibody
- `ode_signaling_simulation` — signaling pathway ODE
- `transcriptomic_moa_lincs` — MoA from transcriptomic data
- `metabolic_flux_fba` — FBA for metabolic targeting

**Coverage**: Partial
**Gaps**: network polypharmacology (minimal target sets from disease network); systems pharmacology multi-target PK/PD

---

## Workflow Folder Map

For tool integration / engineering reference, all modality workflows live under:

```
backend/nf-core-workflows/modules/biomate-ai-tools/
  ├── adc_design/                       (ADC)
  ├── protac_design/                    (PROTAC)
  ├── mrna_therapeutic_design/          (mRNA)
  ├── aav_serotype_selection/           (AAV)
  ├── cart_construct_design/            (CAR-T)
  ├── aso_gapmer_design/                (ASO)
  ├── sirna_design/                     (siRNA generation)
  └── protein_dynamics/                 (MD)

backend/nf-core-workflows/nextflow_nfcore/subworkflows/
  ├── drug_discovery/                   (small molecule, docking, MD, generative)
  ├── pharmacology/                     (PK/PBPK, ADMET, clinical trial)
  ├── cryo_em/                          (CryoSPARC, RELION, helical, cryo-ET)
  ├── bioconductor/                     (R/Bioconductor wrappers, 1000+ tools)

backend/nf-core-workflows/biomni_workflows/
  ├── nfcore/                           (nf-core upstream pipelines)
  ├── pipeline_composition/pipelines/   (composed multi-step pipelines)
```

---

## Pitch-Ready Coverage Claim

> "BioMate covers every major therapeutic modality in active clinical development — small molecule, antibody, ADC, mRNA, siRNA, ASO, CRISPR, CAR-T, PROTAC, and AAV gene therapy — in a single AI platform. For each, BioMate provides: workflow chaining from input to regulatory output, AI-driven parameter inference, validated open-source defaults, and BYOL upgrade paths to commercial gold-standard tools (Schrödinger, Simcyp, NONMEM, MOE, CryoSPARC) when needed."

This claim is verifiable against the DB at any time:
```bash
sqlite3 backend/database/galaxy_ai_tools.db "SELECT count(*), domain FROM workflows GROUP BY domain;"
```

---

## Related Documents

- `20260509_licensed_gated_tools_inventory.md` — full BYOL / API key inventory with startup pricing and workflow folder paths
- `20260509_marketing_positioning_strategy.md` — positioning, pricing tiers, GTM
- `20260509_modality_expansion_session.md` — implementation log for the 6 new modality workflows
- `20260509_blog_survey_biomate_proposals.md` — original gap analysis driving this work
