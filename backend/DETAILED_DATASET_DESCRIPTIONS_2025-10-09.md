# Detailed Dataset and Database Descriptions
**Generated:** 2025-10-09
**Last Updated:** 2025-10-12 (Corrected NL = Neutral Loss terminology)

## MetaboAnalyst SQLite Databases

MS/MS spectral reference databases for metabolite identification via spectral matching.

### Database Overview

| Database | Size | Tables | Category | Primary Use |
| ---------|------|--------|----------|-------------|
| FragsAnnotateDB_v02042024.sqlite | 1.4 GB | 25 | Fragment Annotation | Structure elucidation via fragment matching |
| FragsAnnotateDBNL_v02042024.sqlite | 1.2 GB | 25 | Fragment Annotation (NL) | Neutral loss pattern matching |
| MS2ID_Bio_v09102023.sqlite | 0.7 GB | 25 | Biological | General biological metabolite ID |
| MS2ID_BioNL_v09102023.sqlite | 0.7 GB | 25 | Biological (NL) | Neutral loss matching for biological compounds |
| MS2ID_Exposomics_v09102023.sqlite | 0.7 GB | 25 | Exposomics | Environmental chemical ID |
| MS2ID_ExposomicsNL_v09102023.sqlite | 0.7 GB | 25 | Exposomics (NL) | Neutral loss matching for environmental chemicals |
| MS2ID_Lipids_v09102023.sqlite | 0.7 GB | 25 | Lipidomics | Comprehensive lipid identification |
| MS2ID_LipidsNL_v09102023.sqlite | 0.7 GB | 25 | Lipidomics (NL) | Neutral loss matching for lipids |
| MS2ID_Pathway_v09102023.sqlite | 0.7 GB | 25 | Pathway | Pathway metabolite ID |
| MS2ID_PathwayNL_v09102023.sqlite | 0.7 GB | 25 | Pathway (NL) | Neutral loss matching for pathway metabolites |

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

#### Fragment Annotation Database (Neutral Loss)

**File:** `FragsAnnotateDBNL_v02042024.sqlite`
**Purpose:** Fragment annotation optimized for neutral loss pattern matching (NL = Neutral Loss)

**Description:**
Fragment annotation database optimized for **neutral loss (NL) fragmentation pattern matching** in MS/MS spectra. NL stands for "Neutral Loss" - a mass spectrometry technique that identifies compounds by characteristic neutral fragments lost during fragmentation (e.g., loss of H2O, CO2, NH3, CH3). This database indexes fragments by their neutral loss patterns rather than absolute masses, enabling identification of compounds with characteristic fragmentation behavior. Particularly powerful for compound class identification (e.g., phosphorylated metabolites lose HPO3, glycosides lose sugar moieties). Complements absolute fragment matching by focusing on differential mass losses.

**Data Sources:** MassBank, GNPS, HMDB (neutral loss patterns), literature fragmentation studies

**Use Cases:**
- Neutral loss scan interpretation and annotation
- Compound class identification via characteristic losses
- Phosphorylated metabolite detection (neutral loss of H3PO4)
- Glycoside identification (neutral loss of sugar units)
- Sulfated metabolite detection (neutral loss of SO3)
- Complementary evidence for structure elucidation

**Typical Applications:** Compound class profiling, modified metabolite detection

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

#### MS2ID Biological Metabolites Database (Neutral Loss)

**File:** `MS2ID_BioNL_v09102023.sqlite`
**Purpose:** MS/MS spectral reference optimized for neutral loss matching of biological metabolites (NL = Neutral Loss)

**Description:**
Biological metabolite MS/MS database optimized for **neutral loss (NL) fragmentation pattern matching**. NL stands for "Neutral Loss" - indexing spectra by characteristic neutral fragments lost during MS/MS fragmentation rather than absolute fragment masses. Contains biological metabolites with well-characterized neutral loss patterns: phosphorylated compounds (loss of H3PO4/HPO3), sulfated metabolites (loss of SO3), glucuronides (loss of C6H8O6), glycosides (loss of sugar moieties), and amino acid conjugates (loss of amino acid residues). Enables identification based on diagnostic neutral losses that indicate specific functional groups or modifications.

**Data Sources:** HMDB, KEGG, MassBank (neutral loss-annotated spectra)

**Use Cases:**
- Neutral loss scan data interpretation
- Modified metabolite detection (phosphorylation, sulfation, glycosylation)
- Phase II drug metabolite identification (glucuronidation, sulfation)
- Compound class profiling via diagnostic neutral losses
- Complementary identification evidence alongside fragment matching

**Typical Applications:** Modified metabolite profiling, drug metabolism studies

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

#### MS2ID Exposomics Database (Neutral Loss)

**File:** `MS2ID_ExposomicsNL_v09102023.sqlite`
**Purpose:** MS/MS spectral reference optimized for neutral loss matching of environmental chemicals (NL = Neutral Loss)

**Description:**
Exposomics MS/MS database optimized for **neutral loss (NL) fragmentation pattern matching**. NL stands for "Neutral Loss" - focusing on characteristic neutral fragments lost during MS/MS fragmentation of environmental chemicals and xenobiotics. Contains environmental compounds with diagnostic neutral loss patterns: organophosphate pesticides (loss of CH3OH, C2H5OH), chlorinated compounds (loss of HCl, Cl2), pharmaceuticals with common moieties (loss of CO2, H2O, NH3), and metabolized xenobiotics (loss of glucuronide, sulfate). Enables identification and classification of environmental chemicals based on their characteristic fragmentation behavior.

**Data Sources:** EPA CompTox, NORMAN network, MassBank (environmental spectra)

**Use Cases:**
- Neutral loss screening for pesticide metabolites
- Organophosphate and carbamate detection via diagnostic losses
- Pharmaceutical transformation product identification
- Halogenated compound class profiling (Cl/Br loss patterns)
- Environmental metabolite structure elucidation

**Typical Applications:** Environmental monitoring, pesticide residue analysis

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

#### MS2ID Lipids Database (Neutral Loss)

**File:** `MS2ID_LipidsNL_v09102023.sqlite`
**Purpose:** MS/MS spectral reference optimized for neutral loss matching in lipidomics (NL = Neutral Loss)

**Description:**
Lipidomics MS/MS database optimized for **neutral loss (NL) fragmentation pattern matching**. NL stands for "Neutral Loss" - a critical technique in lipidomics where lipid classes are identified by diagnostic neutral losses. Contains lipid spectra indexed by characteristic neutral loss patterns: phosphatidylcholines (loss of phosphocholine headgroup, 183.066 Da or 59.073 Da in positive mode), phosphatidylethanolamines (loss of 141.019 Da), phosphatidylserines (loss of serine, 87.032 Da), sphingomyelins (loss of phosphocholine, 183.066 Da), and glycerolipids (loss of fatty acid chains as neutral losses). Essential for lipid class identification and fatty acid composition determination via neutral loss scanning.

**Data Sources:** LipidBlast (neutral loss annotations), LIPID MAPS

**Use Cases:**
- Lipid class identification via diagnostic neutral losses
- Fatty acid composition profiling (neutral loss of FA chains)
- Headgroup determination in phospholipids
- Sphingolipid structure elucidation (sphingoid base loss)
- High-confidence lipid class assignments
- Precursor ion and neutral loss scan interpretation

**Typical Applications:** Targeted lipidomics, lipid class profiling

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

#### MS2ID Pathway Database (Neutral Loss)

**File:** `MS2ID_PathwayNL_v09102023.sqlite`
**Purpose:** MS/MS spectral reference optimized for neutral loss matching of pathway metabolites (NL = Neutral Loss)

**Description:**
Pathway metabolite MS/MS database optimized for **neutral loss (NL) fragmentation pattern matching**. NL stands for "Neutral Loss" - indexing pathway metabolite spectra by characteristic neutral fragments lost during MS/MS fragmentation. Contains metabolites from central metabolism with diagnostic neutral loss patterns: phosphorylated intermediates (loss of H3PO4/HPO3), carboxylated compounds (loss of CO2), amino acids (loss of NH3, H2O), CoA derivatives (loss of adenosine moieties), nucleotides (loss of phosphate/ribose), and carbohydrate phosphates (loss of sugar/phosphate units). Enables pathway metabolite identification based on functional group-specific fragmentation patterns.

**Data Sources:** HMDB, KEGG, Reactome, MassBank (pathway metabolite spectra)

**Use Cases:**
- Central metabolism pathway analysis via neutral loss patterns
- Phosphorylated intermediate detection (glycolytic/TCA cycle)
- CoA ester identification (loss of CoA moiety)
- Nucleotide metabolism profiling
- Amino acid and organic acid neutral loss profiling
- Functional group-based metabolite classification

**Typical Applications:** Metabolic pathway analysis, flux studies


**Key Terminology:**

- **NL (Neutral Loss):** Database variant optimized for neutral loss fragmentation pattern matching. Neutral loss is the mass difference between precursor and product ions, indicating loss of specific functional groups (e.g., H2O = 18.015 Da, CO2 = 43.990 Da, NH3 = 17.027 Da)

- **MS/MS Spectral Matching:** Comparing experimental tandem mass spectra to reference spectra for compound identification

- **Precursor m/z:** Mass-to-charge ratio of the parent ion before fragmentation

- **Fragment Annotation:** Identifying and labeling individual fragment peaks in MS/MS spectra

- **Neutral Loss Scanning:** MS/MS acquisition mode that monitors for precursor ions that lose a specific neutral fragment mass, enabling class-specific detection


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

---

## UniProt Protein Databases

### UniProt/Swiss-Prot

**Purpose:** Manually curated protein sequence and functional annotation database

**Description:**
UniProt (Universal Protein Resource) is the most comprehensive, high-quality protein knowledge base. Swiss-Prot is the manually reviewed section containing expert-curated protein entries with experimental evidence. Each entry includes protein sequence, function, structure, post-translational modifications, tissue expression, subcellular localization, disease associations, protein-protein interactions, and extensive literature references. UniProt integrates data from genomics, proteomics, and literature to provide gold-standard protein annotations essential for proteomics, drug discovery, and systems biology research.

**Data Sources:** Manual curation from literature, PDB, EMBL, GenBank, RefSeq, Ensembl

**Key File Types:**

### 1. UniProt FASTA Files (Species-Specific)

**Files:**
- **uniprot_sprot_human.fasta.gz** (7.4 MB) - Human proteome (Homo sapiens, 20,400+ reviewed proteins)
- **uniprot_sprot_mouse.fasta.gz** (7.7 MB) - Mouse proteome (Mus musculus, 17,100+ reviewed proteins)
- **uniprot_sprot_rat.fasta.gz** (7.6 MB) - Rat proteome (Rattus norvegicus, 8,100+ reviewed proteins)

**Purpose:** Protein sequence databases in FASTA format for proteomics searches

**Description:**
Species-specific Swiss-Prot protein sequences in FASTA format. Each entry contains UniProt accession, protein name, gene name, organism, and amino acid sequence. These are reference proteomes containing one representative protein per gene (canonical isoforms). Used as search databases for mass spectrometry-based proteomics (peptide identification via search engines like Mascot, MaxQuant, SEQUEST). Essential for peptide-to-protein mapping, protein quantification, and post-translational modification analysis.

**FASTA Header Format:**
```
>sp|P12345|PROT_HUMAN Protein name OS=Homo sapiens OX=9606 GN=GENE PE=1 SV=3
```
- **sp**: Swiss-Prot entry
- **P12345**: UniProt accession
- **PROT_HUMAN**: Entry name
- **OS**: Organism species
- **OX**: NCBI taxonomy ID
- **GN**: Gene name
- **PE**: Protein existence level (1=experimental evidence, 5=predicted)
- **SV**: Sequence version

**Use Cases:**
- MS/MS proteomics database searches
- Peptide spectrum matching (PSM)
- Protein identification and quantification
- Post-translational modification (PTM) mapping
- Proteogenomics analysis
- Protein isoform detection

### 2. UniProt ID Mapping Files

**Files:**
- **HUMAN_9606_idmapping.dat.gz** (34 MB) - Human protein ID cross-references
- **MOUSE_10090_idmapping.dat.gz** (15 MB) - Mouse protein ID cross-references
- **RAT_10116_idmapping.dat.gz** (12 MB) - Rat protein ID cross-references

**Purpose:** Cross-reference mappings between UniProt IDs and external database identifiers

**Description:**
Comprehensive ID mapping files linking UniProt accessions to 150+ external databases including Ensembl, RefSeq, PDB, NCBI Gene, GO, KEGG, Reactome, STRING, and disease databases (OMIM, Orphanet). Three-column tab-delimited format: UniProt accession, database name, database ID. Essential for integrating proteomic data with genomic, transcriptomic, and pathway databases. Enables conversion between different protein/gene identifier systems used across bioinformatics resources.

**File Format (tab-delimited):**
```
UniProt_AC    Database_Name    Database_ID
P12345        Ensembl          ENSG00000123456
P12345        RefSeq           NP_001234.1
P12345        PDB              1ABC
P12345        GO               GO:0005737
```

**Mapped Databases Include:**
- **Genomic:** Ensembl, RefSeq, NCBI Gene, HGNC, MGI, RGD
- **Structural:** PDB, AlphaFoldDB, BMRB, EMDB
- **Functional:** GO (Gene Ontology), InterPro, Pfam, PROSITE
- **Pathways:** KEGG, Reactome, BioCyc, PathwayCommons
- **Disease:** OMIM, Orphanet, MalaCards, DisGeNET
- **Interactions:** STRING, IntAct, BioGRID, MINT
- **Expression:** Human Protein Atlas, PRIDE, PaxDb
- **Other:** DrugBank, ChEMBL, PubChem, PubMed

**Use Cases:**
- Converting between protein/gene ID systems
- Integrating proteomics with transcriptomics data
- Mapping proteins to pathways and ontologies
- Linking proteins to disease phenotypes
- Retrieving structural information (PDB IDs)
- Protein-protein interaction network analysis
- Cross-database data integration

### 3. UniProt/Swiss-Prot Full Database

**File:** **uniprot_sprot.dat.gz** (655 MB)

**Purpose:** Complete Swiss-Prot database with full annotations in flat-file format

**Description:**
Complete manually curated Swiss-Prot database containing all reviewed protein entries across all organisms (570,000+ proteins from 14,000+ species) in UniProtKB flat-file format. Each entry is a comprehensive record containing: protein sequence, function, catalytic activity, cofactors, enzyme regulation, tissue specificity, developmental stage expression, subcellular localization, post-translational modifications (phosphorylation, glycosylation, acetylation, etc.), protein domains and motifs, 3D structure references, disease associations, genetic variants (SNPs), protein-protein interactions, pathway memberships, and extensive literature citations. This is the most detailed protein annotation resource available.

**Entry Structure (Selected Fields):**
- **ID**: Entry name and length
- **AC**: Primary and secondary accessions
- **DE**: Protein description and nomenclature
- **GN**: Gene names (primary, synonyms, ORF names)
- **OS/OC/OX**: Organism taxonomy
- **CC**: Extensive comments covering:
  - FUNCTION: Biological role
  - CATALYTIC ACTIVITY: Enzyme reactions
  - SUBCELLULAR LOCATION: Cellular compartmentalization
  - TISSUE SPECIFICITY: Expression patterns
  - PTM: Post-translational modifications
  - DISEASE: Associated human diseases
  - INTERACTION: Protein-protein interactions
- **DR**: Cross-references to 150+ databases
- **FT**: Feature table (domains, motifs, modifications, variants)
- **SQ**: Amino acid sequence

**Use Cases:**
- Comprehensive protein functional annotation retrieval
- Enzyme mechanism and regulation information
- Post-translational modification site mapping
- Disease variant interpretation
- Protein localization prediction validation
- Domain and motif analysis
- Protein family classification
- Literature mining and evidence assessment
- Training machine learning models for protein function prediction
- Constructing knowledge graphs

**Typical Applications:**
- Clinical variant interpretation (pathogenicity assessment)
- Drug target validation and characterization
- Systems biology network construction
- Comparative proteomics annotation
- Functional genomics interpretation
- Personalized medicine (variant effects)
