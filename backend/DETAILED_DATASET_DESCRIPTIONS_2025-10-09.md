# Detailed Dataset and Database Descriptions
**Generated:** 2025-10-09

## MetaboAnalyst SQLite Databases

MS/MS spectral reference databases for metabolite identification via spectral matching.

### Database Overview

| Database | Size | Tables | Category | Primary Use |
| ---------|------|--------|----------|-------------|
| FragsAnnotateDB_v02042024.sqlite | 1.4 GB | 25 | Fragment Annotation | Structure elucidation via fragment matching |
| FragsAnnotateDBNL_v02042024.sqlite | 1.2 GB | 25 | Fragment Annotation | Non-lipid fragment matching |
| MS2ID_Bio_v09102023.sqlite | 0.7 GB | 25 | Biological | General biological metabolite ID |
| MS2ID_BioNL_v09102023.sqlite | 0.7 GB | 25 | Biological | Non-lipid biological metabolite ID |
| MS2ID_Exposomics_v09102023.sqlite | 0.7 GB | 25 | Exposomics | Environmental chemical ID |
| MS2ID_ExposomicsNL_v09102023.sqlite | 0.7 GB | 25 | Exposomics | Non-lipid environmental chemical ID |
| MS2ID_Lipids_v09102023.sqlite | 0.7 GB | 25 | Lipidomics | Comprehensive lipid identification |
| MS2ID_LipidsNL_v09102023.sqlite | 0.7 GB | 25 | Lipidomics | Focused lipid identification |
| MS2ID_Pathway_v09102023.sqlite | 0.7 GB | 25 | Pathway | Pathway metabolite ID |
| MS2ID_PathwayNL_v09102023.sqlite | 0.7 GB | 25 | Pathway | Non-lipid pathway metabolite ID |

### Detailed Database Descriptions

#### Fragment Annotation Database

**File:** `FragsAnnotateDB_v02042024.sqlite`  
**Purpose:** Fragment-level MS/MS peak annotation for structure elucidation

**Description:**  
Database for detailed fragment-level annotation of MS/MS spectra. Contains fragmentation patterns, neutral loss patterns, and substructure-fragment associations for metabolite structure elucidation. Each fragment is annotated with its chemical formula, accurate mass, and associated molecular substructure. Used in conjunction with MS2ID databases to provide evidence-based structural information about identified compounds through systematic fragment matching. Improves compound identification confidence by validating that observed fragments match expected fragmentation patterns.

**Data Sources:** Curated from MassBank, GNPS, HMDB, literature fragmentation studies

**Use Cases:**
- MS/MS fragment annotation and validation
- Metabolite substructure identification
- Structure elucidation of unknown compounds
- Improving compound identification confidence scores
- Fragment-based molecular networking
- In-silico fragmentation validation

**Typical Applications:** Unknown metabolite identification, structure validation

#### Fragment Annotation Database (No Lipids)

**File:** `FragsAnnotateDBNL_v02042024.sqlite`  
**Purpose:** Fragment annotation for non-lipid compounds (NL = No Lipids)

**Description:**  
Fragment annotation database with lipid-specific fragmentation patterns excluded. NL stands for "No Lipids". Contains fragment patterns for non-lipid metabolites including amino acids, carbohydrates, organic acids, nucleotides, and other polar compounds. Removes common lipid fragments (fatty acid chains, phosphate head groups, sphingoid bases) to reduce false positives when analyzing non-lipid samples. Recommended for HILIC-MS studies and polar metabolite structure elucidation.

**Data Sources:** MassBank (non-lipid), HMDB (non-lipid fragmentation)

**Use Cases:**
- Non-lipid metabolite fragment annotation
- Polar compound structure elucidation
- HILIC-MS fragment validation
- Reduced false positives from lipid fragments
- Amino acid and carbohydrate fragmentation analysis

**Typical Applications:** Polar metabolomics, amino acid/nucleotide studies

#### MS2ID Biological Metabolites Database

**File:** `MS2ID_Bio_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for comprehensive biological metabolite identification

**Description:**  
Comprehensive MS/MS spectral database for endogenous biological metabolites including all metabolite classes found in biological systems. Contains reference spectra from HMDB (Human Metabolome Database), biological compound collections, and curated metabolomics resources. Covers sugars, amino acids, organic acids, nucleotides, lipids, vitamins, hormones, and other endogenous compounds. Ideal for broad-scope untargeted metabolomics where the chemical space of interest is biological/endogenous metabolites.

**Data Sources:** HMDB, BioCyc, KEGG, Reactome, MoNA biological subset

**Use Cases:**
- Untargeted metabolomics discovery studies
- Comprehensive metabolite profiling
- Biomarker discovery in clinical samples
- Disease metabolomics research
- General identification of biological compounds

**Typical Applications:** Clinical diagnostics, biomarker discovery, nutritional studies

#### MS2ID Biological Metabolites Database (No Lipids)

**File:** `MS2ID_BioNL_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for non-lipid biological metabolites (NL = No Lipids)

**Description:**  
Biological metabolite database with all lipid compounds removed. NL stands for "No Lipids". Includes polar and semi-polar biological metabolites: amino acids, organic acids, carbohydrates, nucleotides, vitamins, neurotransmitters, hormones (non-steroid), and other water-soluble endogenous compounds. Recommended when lipidomics is not part of the study design or when using chromatography methods optimized for polar metabolites (HILIC, ion-pairing RP).

**Data Sources:** HMDB (non-lipid entries), KEGG (polar metabolites)

**Use Cases:**
- Polar metabolite profiling in biological samples
- Non-lipid biomarker discovery
- HILIC or ion-pair chromatography-MS workflows
- Aqueous metabolite extraction studies
- Reduced database for faster, focused searches

**Typical Applications:** Urine/serum polar metabolomics, neurotransmitter analysis

#### MS2ID Exposomics Database

**File:** `MS2ID_Exposomics_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for environmental chemicals, pollutants, and xenobiotics

**Description:**  
Specialized MS/MS database for exposome research containing environmental chemicals, industrial pollutants, pesticides, herbicides, pharmaceuticals, personal care products, food additives, and other xenobiotic compounds. Curated for exposomics studies investigating environmental chemical exposures and their health effects. Includes compounds from EPA databases, pharmaceutical databases, and environmental monitoring programs. Essential for studies linking environmental exposures to health outcomes.

**Data Sources:** EPA CompTox, DrugBank, PubChem (environmental subset), NORMAN network

**Use Cases:**
- Environmental exposure assessment studies
- Toxicology and ecotoxicology research
- Pharmaceutical and drug metabolite detection
- Food contaminant and additive analysis
- Occupational health exposure monitoring
- Water, air, and soil contamination studies

**Typical Applications:** Environmental health, toxicology, regulatory monitoring

#### MS2ID Exposomics Database (No Lipids)

**File:** `MS2ID_ExposomicsNL_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for non-lipid environmental chemicals (NL = No Lipids)

**Description:**  
Exposomics database with lipophilic pollutants excluded. NL stands for "No Lipids". Contains water-soluble environmental chemicals, polar pesticides, pharmaceutical compounds, and other non-lipid xenobiotics. Focuses on compounds with log P < 3 that are typically found in aqueous environmental matrices (surface water, groundwater, wastewater). Use for studies targeting polar exposome compounds or when using chromatography optimized for polar analytes.

**Data Sources:** EPA CompTox (polar subset), NORMAN suspect list

**Use Cases:**
- Water quality monitoring and analysis
- Polar pesticide and herbicide detection
- Pharmaceutical pollutant screening in wastewater
- Drinking water contamination studies
- Non-lipid food additive analysis

**Typical Applications:** Water quality studies, pharmaceutical environmental fate

#### MS2ID Lipids Database

**File:** `MS2ID_Lipids_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for comprehensive lipidomics

**Description:**  
Comprehensive lipidomics MS/MS database containing reference spectra for lipids and lipid-like molecules across all major lipid categories: fatty acyls (FA), glycerolipids (GL), glycerophospholipids (GP), sphingolipids (SP), sterols (ST), prenol lipids (PR), saccharolipids (SL), and polyketides (PK). Curated from LipidBlast, LIPID MAPS Structure Database, LipidBank, and other lipidomics resources. Includes positive and negative ion mode spectra with multiple collision energies. Essential for lipidomics studies investigating lipid metabolism, membrane composition, and lipid biomarkers.

**Data Sources:** LipidBlast, LIPID MAPS, LipidBank, SwissLipids, HMDB lipids

**Use Cases:**
- Comprehensive lipidomics profiling
- Lipid biomarker discovery in disease
- Membrane lipid composition analysis
- Lipid metabolism pathway studies
- Cardiovascular and metabolic disease research
- Lipid class and species identification

**Typical Applications:** Clinical lipidomics, lipid metabolism, membrane biology

#### MS2ID Lipids Database (Subset)

**File:** `MS2ID_LipidsNL_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for focused lipidomics (reduced database)

**Description:**  
Curated subset of the comprehensive lipids database. Despite "NL" in the filename, this database DOES contain lipids - the "NL" likely refers to a different filtering criterion (possibly "No Low-abundance" or "No Lipid-like" non-lipid compounds). Contains core lipid classes with high-quality reference spectra: major glycerophospholipids (PC, PE, PS, PI, PG), sphingolipids (SM, Cer), and abundant glycerolipids (TG, DG). Recommended for targeted lipidomics or when faster search times are needed with a focused lipid scope.

**Data Sources:** LipidBlast (curated), LIPID MAPS (major classes)

**Use Cases:**
- Targeted lipidomics for major lipid classes
- Clinical lipid profiling (major species)
- High-throughput lipidomics with faster searches
- Focused membrane phospholipid analysis
- Lipid quality control and method development

**Typical Applications:** Clinical lipidomics, high-throughput screening

#### MS2ID Pathway Database

**File:** `MS2ID_Pathway_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for pathway metabolite identification

**Description:**  
MS/MS spectral matching database containing reference spectra for metabolites involved in biological pathways from KEGG, Reactome, and other pathway databases. Used for compound identification by comparing experimental tandem mass spectra against known pathway metabolites. Contains precursor m/z, retention time, collision energy, and fragment spectra for metabolites in central carbon metabolism, TCA cycle, glycolysis, amino acid metabolism, and other core biochemical pathways.

**Data Sources:** HMDB, KEGG, Reactome, MoNA, MassBank

**Use Cases:**
- Targeted pathway metabolomics analysis
- MS/MS spectral matching for pathway compounds
- Functional metabolomics and pathway enrichment
- Metabolic flux analysis
- Faster searches (130 MB database) for pathway-focused studies

**Typical Applications:** Clinical metabolomics, systems biology, drug metabolism

#### MS2ID Pathway Database (No Lipids)

**File:** `MS2ID_PathwayNL_v09102023.sqlite`  
**Purpose:** MS/MS spectral reference for non-lipid pathway metabolites (NL = No Lipids)

**Description:**  
Subset of pathway database with all lipid compounds excluded. NL stands for "No Lipids". Contains only polar metabolites from central metabolism including carbohydrates, amino acids, organic acids, nucleotides, vitamins, and cofactors. Use this database when analyzing non-lipid pathway metabolites to reduce database size, improve search speed, and eliminate false matches from lipid fragmentation patterns.

**Data Sources:** HMDB (non-lipid), KEGG (non-lipid pathways), Reactome

**Use Cases:**
- Polar metabolite analysis in HILIC or RP-LC
- Central carbon and nitrogen metabolism studies
- Amino acid, nucleotide, and organic acid profiling
- Reduced search space for faster processing
- Studies explicitly excluding lipidomics

**Typical Applications:** HILIC-MS metabolomics, targeted amino acid analysis


**Key Terminology:**  

- **NL (No Lipids):** Database variant with lipid compounds excluded for focused non-lipid analysis

- **MS/MS Spectral Matching:** Comparing experimental tandem mass spectra to reference spectra for compound identification

- **Precursor m/z:** Mass-to-charge ratio of the parent ion before fragmentation

- **Fragment Annotation:** Identifying and labeling individual fragment peaks in MS/MS spectra


## Local Datasets - Detailed Descriptions

### BindingDB

**Purpose:** Drug-target binding affinity measurements

**Description:**  
Comprehensive database of measured binding affinities between drug-like small molecules and protein targets. Contains over 3 million binding data points for 1.3 million compounds and 9,600 targets. Includes multiple types of binding measurements: Ki (inhibition constant), Kd (dissociation constant), IC50 (half-maximal inhibitory concentration), and thermodynamic parameters (ΔG, ΔH, -TΔS). Data derived from published literature and high-throughput screening campaigns. Essential resource for drug discovery, target validation, and structure-activity relationship (SAR) studies.

**Key Columns:**
- ligand_id: Compound identifier (InChI, SMILES, PubChem CID)
- target_id: Protein target identifier (UniProt, PDB)
- affinity_type: Type of measurement (Ki, Kd, IC50, EC50)
- affinity_value: Binding affinity value with units (nM, μM, etc.)
- assay_conditions: pH, temperature, buffer conditions
- reference: PubMed ID or patent number

**Use Cases:**
- Virtual screening and drug repurposing
- QSAR model development
- Target selectivity analysis
- Lead optimization in drug discovery
- Polypharmacology prediction

### DepMap_CRISPR

**Purpose:** Cancer cell line gene dependency from CRISPR screens

**Description:**  
Cancer Dependency Map (DepMap) data from genome-scale CRISPR-Cas9 knockout screens across 800+ cancer cell lines. Each gene is scored for essentiality (dependency) using the CERES algorithm, which corrects for copy number effects and sgRNA efficiency. Negative scores indicate cell death upon gene knockout (essential), while scores near zero indicate no effect (non-essential). Integrated with genomic, transcriptomic, and proteomic data for each cell line. Identifies cancer-specific vulnerabilities for precision oncology drug target discovery.

**Key Columns:**
- cell_line: Cancer cell line name (e.g., A549, HeLa) with tissue type
- gene: Gene symbol (HUGO nomenclature)
- dependency_score: CERES-corrected essentiality score (negative = essential)
- effect_size: Raw knockout effect before correction
- cell_line_metadata: Tissue, cancer type, molecular subtype
- genomic_features: Mutations, CNV, expression levels

**Included Datasets:**
- **CRISPRGeneDependency:** Gene-level dependency scores (CERES)
- **CRISPRGeneEffect:** Raw effect sizes before correction
- **Model:** Cell line metadata, tissue types, molecular features
- **OmicsExpressionProteinCodingGenesTPMLogp1:** Gene expression (RNA-seq TPM)

**Use Cases:**
- Cancer drug target identification
- Synthetic lethality discovery
- Precision oncology biomarker development
- Understanding cancer-specific dependencies
- Therapeutic target validation

### DDInter

**Purpose:** Drug-drug interaction database for clinical safety

**Description:**  
Comprehensive database of clinically significant drug-drug interactions (DDIs) with over 302,000 interaction records involving 2,310 drugs. Each DDI is annotated with mechanism of action, severity level (contraindicated, major, moderate, minor), clinical significance, management strategies, and alternative medications. Organized by therapeutic class (alimentary, cardiovascular, CNS, antineoplastic, etc.). Version 2.0 includes drug-disease-supplement interactions (DDSI), drug-food interactions (DFI), and therapeutic duplication warnings. Essential for prescription checking, clinical decision support, and polypharmacy management.

**Key Columns:**
- drug1 & drug2: Interacting drug names (generic and brand)
- interaction_type: Pharmacokinetic vs. pharmacodynamic
- severity: Contraindicated, major, moderate, minor
- mechanism: Detailed description of interaction mechanism
- clinical_effect: Observed clinical consequences
- management: Recommendations for safe co-administration
- alternative_medications: Safer drug alternatives
- evidence_level: Clinical study support strength

**Therapeutic Classes:**
- **alimentary_tract_metabolism:** GI drugs, antacids, diabetes medications
- **antineoplastic:** Cancer chemotherapy and targeted therapy
- **antiparasitic:** Antimalarials, anthelmintics
- **blood_organs:** Anticoagulants, antiplatelets, hematopoietics
- **cardiovascular:** Antihypertensives, antiarrhythmics, statins
- **dermatological:** Topical and systemic skin medications
- **hormonal:** Hormones, contraceptives, diabetes drugs
- **nervous_system:** CNS drugs, antidepressants, antipsychotics
- **respiratory:** Bronchodilators, antihistamines, decongestants
- **various:** Other therapeutic categories

**Use Cases:**
- Prescription safety checking
- Clinical decision support systems
- Polypharmacy risk assessment
- Drug interaction prediction models
- Pharmaceutical care optimization

### EveBio

**Purpose:** Evolutionary-based bioactivity database

**Description:**  
Curated database linking chemical compounds to biological assays through evolutionary relationships. Contains compound structures, bioassay data, bundle classifications (groups of related assays), and compound-assay activity matrices. Integrates data from ChEMBL, PubChem BioAssay, and literature. Uses evolutionary algorithms to predict bioactivity and identify compound-target associations. Useful for drug repurposing, target prediction, and understanding compound polypharmacology.

**Included Datasets:**
- **assay_table:** Biological assays with target information
- **bundle_table:** Assay bundles (grouped related assays)
- **compound_table:** Chemical structures and identifiers
- **activity_table:** Compound-assay activity measurements
- **prediction_table:** Predicted bioactivities
- **target_table:** Target protein information
- **chembl_mapping:** Cross-references to ChEMBL
- **pubchem_mapping:** Cross-references to PubChem

**Use Cases:**
- Drug repurposing and repositioning
- Target prediction for compounds
- Bioactivity prediction
- Multi-target drug design
- Chemical-biological space mapping

### CRISPR_sgRNA

**Purpose:** CRISPR sgRNA libraries for genome-scale knockout screens

**Description:**  
Genome-scale CRISPR single guide RNA (sgRNA) library sequences for human and mouse. Contains ~5 sgRNAs per gene targeting all protein-coding genes plus controls. Includes sgRNA sequence (20 nt), PAM sequence, genomic coordinates, target gene, on-target and off-target scores, and predicted cutting efficiency. Used for designing CRISPR knockout screens, analyzing screen results, and identifying high-quality sgRNAs for gene editing experiments. Libraries are optimized for minimal off-target effects (Specificity Score, SP).

**Key Columns:**
- sgRNA_sequence: 20 nucleotide guide sequence
- PAM_sequence: Protospacer adjacent motif (NGG for SpCas9)
- target_gene: Gene symbol and Ensembl ID
- genomic_location: Chromosome, start, end, strand
- KO_score: Predicted knockout efficiency
- SP_score: Specificity score (1 = unique, <1 = off-targets)
- off_target_sites: Number and location of potential off-targets

**Files:**
- **sgRNA_KO_SP_human.txt:** Human genome-scale sgRNA library (~90K sgRNAs, 18K genes)
- **sgRNA_KO_SP_mouse.txt:** Mouse genome-scale sgRNA library (~87K sgRNAs, 17K genes)

**Use Cases:**
- Genome-scale CRISPR screen design
- sgRNA selection for gene knockout
- CRISPR screen data analysis
- Off-target effect prediction
- Gene essentiality studies
