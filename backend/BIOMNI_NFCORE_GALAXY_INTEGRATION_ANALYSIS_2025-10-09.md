# Biomni & nf-core → Galaxy Integration Analysis
**Date:** 2025-10-09
**Purpose:** Comprehensive analysis of biomni and nf-core tools/resources for Galaxy integration

---

## Executive Summary

### Current Coverage Status

| Platform | Total Tools/Modules | In Galaxy | Not in Galaxy | Galaxy Coverage |
|----------|---------------------|-----------|---------------|-----------------|
| **Galaxy ToolShed** | 6,295 unique tools | - | - | 100% (baseline) |
| **Biomni** | 119 unique tools/libs | 30 (27.5%) | 79 (72.5%) | 27.5% |
| **nf-core** | 98 modules | 40 (40.8%) | 58 (59.2%) | 40.8% |

**Key Insight:**
- **79 biomni tools** and **58 nf-core modules** are NOT currently in Galaxy
- Combined potential: **137 unique tools** to extend Galaxy's capabilities
- Overlap between biomni and nf-core: Only 5 tools (fastqc, mafft, trimmomatic, iqtree2, cellpose)

---

## Part 1: Biomni Updates Analysis

### 1.1 Recent Git Updates (Last 10 Commits)

**Key Changes Since Sept 2024:**

1. **Synapse Integration (NEW)** - Commit 6e4a539, 1dcc306
   - Added `query_synapse()` function for biomedical dataset access
   - Supports authentication via `SYNAPSE_AUTH_TOKEN`
   - Location: `biomni/tool/database.py`
   - **Use Case:** Access genomics and clinical research datasets from Synapse platform

2. **LazySlide Support (NEW)** - Commit d146ad7, 9931186, 0c66fc9
   - Added `lazyslide` Python package for whole slide image analysis
   - Enables histopathology workflows (preprocessing → deep learning)
   - Location: `biomni/env_desc.py:94`
   - **Use Case:** Reproducible, interoperable whole slide image analysis

3. **ClinicalTrials.gov Integration** - Commit 2bd9f68
   - Added `query_clinicaltrials()` function
   - REST API access to clinical trials data
   - **Use Case:** Query clinical trial information for drug research

4. **Tool Optimizations** - Commit 5f540c2
   - Performance improvements across tool modules
   - Enhanced database query functions

5. **Config Management Improvements** - Commit 3781116, 35a86e1
   - Better API key and LLM model configuration
   - Fixes for parameter naming

### 1.2 Biomni Data Lakes (79 Datasets)

**New/Notable Data Lakes:**

#### Drug Discovery & Pharmacology
- `BindingDB_All_202409.tsv` - Binding affinities (proteins ↔ small molecules)
- `broad_repurposing_hub_molecule_with_smiles.parquet` - Broad Institute drug library
- `evebio_*_table.csv` (7 files) - EveBio pharmome screening data
  - Assay, target, compound metadata
  - Summary results with IC50/EC50 values
  - Raw observed datapoints

#### Cancer Biology
- `DepMap_CRISPRGeneDependency.csv` - Gene dependency for cancer cell lines
- `DepMap_CRISPRGeneEffect.csv` - CRISPR knockout effects
- `DepMap_OmicsExpressionProteinCodingGenesTPMLogp1.csv` - Gene expression (TPM)

#### Drug-Drug Interactions (DDInter 2.0)
- `ddinter_*.csv` (8 files) - Drug interactions by therapeutic class
  - alimentary_tract_metabolism, antineoplastic, antiparasitic
  - blood_organs, dermatological, hormonal, respiratory, various

#### Single-Cell & Genomics
- `czi_census_datasets_v4.parquet` - CZI Cell Census
- `gtex_tissue_gene_tpm.parquet` - GTEx tissue expression
- `McPAS-TCR.parquet` - T-cell receptor sequences

#### Genetic Variants
- `genebass_*_filtered.pkl` (3 files) - GeneBass variants
  - missense_LC, pLoF (loss-of-function), synonymous
- `variant_table.parquet` - Annotated variants

#### Knowledge Graphs & Ontologies
- `kg.csv` - Precision medicine KG (17,080 diseases, 4M+ relationships)
- `go-plus.json` - Gene ontology
- `hp.obo` - Human Phenotype Ontology

#### Gene Sets (MSigDB & MouseMine)
- `msigdb_human_c*_geneset.parquet` (9 files)
  - Positional, curated, regulatory, computational, ontology
  - Oncogenic, immunologic, cell type signatures, hallmarks
- `mousemine_m*_geneset.parquet` (5 files)

### 1.3 Biomni Database APIs (31 Functions)

**Complete List:**

| API Function | Database | Description |
|--------------|----------|-------------|
| `query_uniprot` | UniProt | Protein sequences, annotations |
| `query_alphafold` | AlphaFold | Protein structure predictions |
| `query_interpro` | InterPro | Protein domains & families |
| `query_pdb` | RCSB PDB | Protein structures |
| `query_kegg` | KEGG | Pathways, genomes, chemicals |
| `query_stringdb` | STRING | Protein-protein interactions |
| `query_iucn` | IUCN Red List | Species conservation status |
| `query_paleobiology` | PBDB | Fossil records |
| `query_jaspar` | JASPAR | Transcription factor binding |
| `query_worms` | WoRMS | Marine species taxonomy |
| `query_cbioportal` | cBioPortal | Cancer genomics |
| `query_clinvar` | ClinVar | Clinical genetic variants |
| `query_geo` | GEO | Gene expression datasets |
| `query_dbsnp` | dbSNP | SNP database |
| `query_ucsc` | UCSC Genome | Genome browser data |
| `query_ensembl` | Ensembl | Genome annotations |
| `query_opentarget` | Open Targets | Target-disease associations |
| `query_monarch` | Monarch | Disease-gene associations |
| `query_openfda` | OpenFDA | FDA adverse events |
| `query_clinicaltrials` | ClinicalTrials.gov | **NEW** Clinical trials |
| `query_gwas_catalog` | GWAS Catalog | GWAS associations |
| `query_gnomad` | gnomAD | Population variant frequencies |
| `query_reactome` | Reactome | Biological pathways |
| `query_regulomedb` | RegulomeDB | Regulatory variants |
| `query_pride` | PRIDE | Proteomics datasets |
| `query_gtopdb` | Guide to Pharmacology | Drug targets |
| `query_remap` | ReMap | Regulatory regions |
| `query_mpd` | Mouse Phenome | Mouse phenotypes |
| `query_emdb` | EMDB | Electron microscopy |
| `query_synapse` | Synapse | **NEW** Biomedical datasets |
| `get_hpo_names` | HPO | Phenotype ontology terms |

### 1.4 Biomni Software/Tools Library (161 Items)

**Categorized by Type:**

#### Python Packages (91 packages)
**Core Bioinformatics:**
- biopython, biom-format, scanpy, scikit-bio, anndata, mudata
- pyliftover, biopandas, biotite, **lazyslide (NEW)**
- gget, lifelines, gseapy, scrublet, cellxgene-census
- scvelo, pysam, pyfaidx, pyranges, pybedtools

**Genomics & Sequencing:**
- pysam, pyfaidx, pyranges, pybedtools, pyBigWig, cyvcf2

**Single-Cell Analysis:**
- scanpy, anndata, mudata, scvelo, scrublet, pyscenic

**Structural Biology & Drug Discovery:**
- rdkit, deeppurpose, pyscreener, openbabel, descriptastorus
- openmm, pytdc, pymol (commented), pdbfixer

**Metabolomics & Mass Spec:**
- PyMassSpec, pymzml, cooler

**Network & Systems Biology:**
- pyscenic, igraph, arboreto, cobra, python-libsbml

**Statistical & ML:**
- pandas, numpy, scipy, scikit-learn, matplotlib, seaborn
- statsmodels, pymc3, umap-learn, faiss-cpu, harmony-pytorch

**Specialty Tools:**
- cellpose (cell segmentation), viennarna (RNA), trackpy (particle tracking)
- mageck (CRISPR screens), loompy, fanc (chromatin), hmmlearn
- msprime, tskit (population genetics)

#### R Packages (11 packages)
- **Core:** ggplot2, dplyr, tidyr, readr, stringr, Matrix
- **Bioinformatics:** DESeq2, clusterProfiler, edgeR, limma, WGCNA, harmony

#### CLI Tools (23 tools)
- **Sequence Analysis:** samtools, bowtie2, bwa, bedtools
- **Quality Control:** fastqc, trimmomatic
- **Alignment:** mafft, muscle, MAFFT
- **Phylogenetics:** iqtree2, FastTree
- **ChIP-seq:** macs2, Homer
- **Genetics:** plink, plink2, gcta64
- **Molecular Docking:** ADFR, vina, autosite
- **Other:** diamond, fcsparser, plannotate

---

## Part 2: nf-core Modules Analysis

### 2.1 nf-core Module Coverage

**Total Modules:** 98
**In Galaxy:** 40 (40.8%)
**NOT in Galaxy:** 58 (59.2%)

### 2.2 nf-core Modules NOT in Galaxy (58 modules)

**High-Priority for Galaxy Integration:**

#### Sequencing Quality & Preprocessing (15 modules)
- `cutadapt`, `trimgalore`, `prinseqplusplus` - Read trimming
- `nanoplot`, `toulligqc`, `checkqc` - QC for long/short reads
- `pychopper` - Nanopore cDNA analysis
- `mosdepth` - Depth coverage
- `dupradar` - Duplication analysis
- `phantompeakqualtools` - ChIP-seq QC

#### Assembly & Variant Calling (12 modules)
- `spades`, `megahit`, `hifiasm` - Genome assembly
- `trinity` - Transcriptome assembly
- `clair3`, `sniffles`, `cutesv` - Variant calling (long reads)
- `vcftools`, `vcfanno`, `vcf2cytosure`, `svync` - VCF manipulation
- `haplocheck` - Haplogroup checking

#### Annotation & Functional Analysis (8 modules)
- `interproscan` - Protein domain/function
- `prokka`, `pyrodigal` - Gene prediction
- `ampir` - Antimicrobial peptide prediction
- `argnorm` - ARG normalization
- `sourcepredict` - Source attribution
- `pirate` - Pangenome analysis

#### Specialized Tools (23 modules)
- **Proteomics:** `thermorawfileparser` - Mass spec data
- **Phylogenetics:** `seq2hla` - HLA typing
- **Cell Biology:** `cellpose` - Cell segmentation
- **Long-read:** `lima`, `pbccs`, `hiphase` - PacBio processing
- **Metagenomics:** `maxbin2` - Binning
- **Utilities:** `multiqc`, `bioawk`, `humid`, `fastavalidator`
- **File Handling:** `unzip`, `unzipfiles`, `untar`, `md5sum`, `aria2`
- **Specialized:** `bclconvert`, `smoothxg`, `blat`, `smncopynumbercaller`
- **Reporting:** `datavzrd`, `quartonotebook`
- **Copy Number:** `upd` - Uniparental disomy detection

### 2.3 Tools in All Three Platforms (3 tools only)

Only **3 tools** are in Galaxy, Biomni, AND nf-core:
1. **fastqc** - Quality control (7 Galaxy tools, 1 biomni, 1 nfcore)
2. **mafft** - Multiple sequence alignment (9 Galaxy tools)
3. **trimmomatic** - Read trimming (1 Galaxy tool)

**Note:** iqtree2 and cellpose are in biomni + nfcore but have different naming in Galaxy (iqtree vs iqtree2)

---

## Part 3: Integration Requirements for Galaxy

### 3.1 Unique Tools to Add to Galaxy

Based on overlap analysis:

#### From Biomni (79 unique tools NOT in Galaxy)

**Priority Tier 1 - Scientific Computing Core (15 tools):**
1. `rdkit` - Cheminformatics (critical for LC-MS workflows)
2. `deeppurpose` - Drug-target interaction ML
3. `scanpy` - Single-cell analysis (widely used)
4. `lazyslide` - Whole slide image analysis (NEW)
5. `pyscenic` - Gene regulatory networks
6. `cellpose` - Cell segmentation (also in nfcore)
7. `scvelo` - RNA velocity
8. `cobra` - Metabolic modeling
9. `cooler` - Hi-C data analysis
10. `viennarna` - RNA structure prediction
11. `mageck` - CRISPR screen analysis
12. `gseapy` - Gene set enrichment
13. `lifelines` - Survival analysis
14. `pymc3` - Bayesian statistics
15. `harmony-pytorch` - Data integration

**Priority Tier 2 - R Bioinformatics (7 tools):**
1. `DADA2` - Amplicon error correction
2. `WGCNA` - Network analysis
3. `Seurat` - Single-cell (R version)
4. `clusterProfiler` - Functional enrichment
5. `FlowCore` - Flow cytometry
6. `AnnotationDbi` - Annotation databases
7. `GO.db` - Gene ontology

**Priority Tier 3 - CLI Bioinformatics (12 tools):**
1. `diamond` - Fast sequence alignment
2. `muscle` - Multiple alignment
3. `iqtree2` - Phylogenetics
4. `gcta` - GWAS analysis
5. `plink2` - Genetic association
6. `Homer` - Motif discovery
7. `FastTree` - Phylogeny
8. `plannotate` - Plasmid annotation
9. `vina` - Molecular docking
10. `ADFR` - AutoDock
11. `trnascan-se` - tRNA prediction
12. `blast+` - NCBI BLAST

**Priority Tier 4 - Python Utilities (30+ remaining):**
- Data handling: pandas, numpy, scipy, h5py, tiledb
- Image analysis: opencv-python, scikit-image
- Literature: pymed, arxiv, scholarly
- Specialized: biotite, biopandas, pybigwig, etc.

#### From nf-core (58 unique modules NOT in Galaxy)

**Priority Tier 1 - High-Impact Tools (20 modules):**
1. `interproscan` - Protein annotation (widely used)
2. `prokka` - Bacterial annotation
3. `spades` - Genome assembler
4. `megahit` - Metagenome assembler
5. `trinity` - RNA-seq assembler
6. `multiqc` - Multi-tool QC aggregation
7. `cutadapt` - Adapter trimming
8. `trimgalore` - Wrapper for cutadapt+fastqc
9. `vcftools` - VCF manipulation
10. `clair3` - Variant caller (long reads)
11. `sniffles` - SV caller
12. `nanoplot` - Nanopore QC
13. `mosdepth` - Coverage analysis
14. `hifiasm` - HiFi assembler
15. `lima` - PacBio demultiplexing
16. `pbccs` - PacBio CCS
17. `thermorawfileparser` - Mass spec
18. `cellpose` - Cell segmentation (overlap with biomni)
19. `bioawk` - AWK for bioinformatics
20. `datavzrd` - Interactive data viz

**Priority Tier 2 - Specialized Tools (38 remaining nfcore modules)**
- See section 2.2 for complete list

### 3.2 Database API Integration

**31 Biomni database APIs** should be exposed as Galaxy tools:

**Implementation Approach:**
1. Create Galaxy tool wrappers for each `query_*` function
2. Support both:
   - Natural language queries (using LLM)
   - Direct structured queries
3. Return results in Galaxy-compatible formats:
   - Tabular (TSV/CSV)
   - JSON
   - FASTA/VCF (for sequence/variant queries)

**Example Galaxy Tool for query_uniprot:**
```xml
<tool id="biomni_query_uniprot" name="Query UniProt">
  <description>Search UniProt protein database</description>
  <inputs>
    <param name="query_type" type="select" label="Query Type">
      <option value="natural">Natural Language</option>
      <option value="structured">Structured Query</option>
    </param>
    <param name="prompt" type="text" label="Natural Language Query"
           help="E.g., 'Find human kinases involved in cell cycle'"/>
    <param name="endpoint" type="text" label="API Endpoint (optional)"/>
  </inputs>
  <outputs>
    <data name="output" format="tabular"/>
  </outputs>
  <command>
    python biomni_uniprot_wrapper.py
      --query-type "$query_type"
      --prompt "$prompt"
      --endpoint "$endpoint"
      --output "$output"
  </command>
</tool>
```

### 3.3 Data Lake Access

**79 Biomni data lake files** should be:

1. **Hosted in Galaxy Data Libraries**
   - Create "Biomni Data Lake" library
   - Organize by category (Drug Discovery, Cancer, Single-Cell, etc.)
   - Total size estimate: ~50-100 GB

2. **Accessible via Tools**
   - Create "Load Biomni Dataset" tool
   - Parameters:
     - Dataset selector (dropdown from data_lake_dict)
     - Output format (parquet → tabular conversion)
   - Integration with existing Galaxy datasets

3. **API-Based Access (Alternative)**
   - For large datasets (e.g., BindingDB, DepMap)
   - Query interface instead of full download
   - Reduces storage requirements

---

## Part 4: Implementation Roadmap

### Phase 1: Database & Data Lake Integration (Week 1-2)

**Tasks:**
1. ✅ Analyze biomni updates - COMPLETED
2. Create Galaxy tool wrappers for 31 database APIs
3. Set up Biomni Data Lake in Galaxy Data Libraries
4. Test database query tools with sample workflows

**Deliverables:**
- 31 Galaxy tools (`biomni_query_*.xml`)
- Data lake catalog in Galaxy
- Documentation for database queries

### Phase 2: Priority Tier 1 Tools (Week 3-4)

**Biomni Tools (15):**
1. rdkit, deeppurpose, scanpy, lazyslide, pyscenic
2. cellpose, scvelo, cobra, cooler, viennarna
3. mageck, gseapy, lifelines, pymc3, harmony-pytorch

**nf-core Modules (20):**
1. interproscan, prokka, spades, megahit, trinity
2. multiqc, cutadapt, trimgalore, vcftools, clair3
3. sniffles, nanoplot, mosdepth, hifiasm, lima
4. pbccs, thermorawfileparser, cellpose, bioawk, datavzrd

**Implementation:**
- Create Galaxy tool XML definitions
- Write Python wrapper scripts
- Add to galaxy_ai_tools.db with parameters
- Test in sample workflows

### Phase 3: Priority Tier 2 & 3 Tools (Week 5-6)

**Biomni Tools (19):**
- R packages (7): DADA2, WGCNA, Seurat, clusterProfiler, FlowCore, AnnotationDbi, GO.db
- CLI tools (12): diamond, muscle, iqtree2, gcta, plink2, etc.

**nf-core Modules (38 remaining)**

**Approach:**
- Semi-automated tool generation using templates
- Batch testing
- Parameter extraction from documentation

### Phase 4: Integration & Testing (Week 7-8)

**Tasks:**
1. Update galaxy_ai_tools.db with ALL new tools
2. Rebuild FTS5 search index
3. Test workflow generator with new tools
4. Create example workflows for:
   - LC-MS metabolomics (using rdkit, xcms data)
   - Single-cell RNA-seq (using scanpy, scvelo)
   - Metagenomics (using megahit, prokka)
   - Drug discovery (using deeppurpose, BindingDB)
5. Performance testing
6. Documentation

### Phase 5: Platform Consolidation (Week 9-10)

**Create Unified Biomate Platform:**
1. Integrate all three platforms:
   - Galaxy (6,295 tools) + Biomni (161 tools) + nf-core (98 modules)
2. Cross-platform workflow compatibility
3. Unified search across all tools
4. Data lake + database API access
5. AI-powered workflow generation using comprehensive index

**Expected Final Coverage:**
- **~6,500 total tools** in Galaxy after integration
- **79 biomni data lakes** accessible
- **31 database APIs** available
- **100% coverage** of biomni and nfcore capabilities

---

## Part 5: Technical Specifications

### 5.1 Tool Wrapper Template

**Standard Galaxy Tool XML Structure:**

```xml
<tool id="biomni_{tool_name}" name="{Tool Name}" version="{version}">
  <description>{one-line description}</description>

  <requirements>
    <requirement type="package" version="{version}">{package_name}</requirement>
  </requirements>

  <command detect_errors="exit_code"><![CDATA[
    python '$__tool_directory__/{tool_name}_wrapper.py'
      #for $param in $parameters:
        --${param.name} '${param.value}'
      #end for
      --output '$output'
  ]]></command>

  <inputs>
    <!-- Auto-generated from biomni/nfcore parameter extraction -->
  </inputs>

  <outputs>
    <data name="output" format="tabular" label="${tool.name} on ${on_string}"/>
  </outputs>

  <help><![CDATA[
    {help_text from biomni env_desc.py or nfcore docs}
  ]]></help>

  <citations>
    <!-- Auto-populated from tool metadata -->
  </citations>
</tool>
```

### 5.2 Database Schema Extension

**Add to galaxy_ai_tools.db:**

```sql
-- New table for external tool sources
CREATE TABLE tool_sources (
    tool_id TEXT PRIMARY KEY,
    source_platform TEXT, -- 'biomni', 'nfcore', 'galaxy', 'biomate_custom'
    source_url TEXT,
    biomni_category TEXT, -- e.g., 'genomics', 'database', 'support_tools'
    nfcore_module TEXT,
    data_lake_access BOOLEAN DEFAULT 0,
    api_access BOOLEAN DEFAULT 0,
    FOREIGN KEY (tool_id) REFERENCES tools (id)
);

-- New table for data lake mappings
CREATE TABLE data_lakes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT UNIQUE,
    description TEXT,
    category TEXT,
    size_mb REAL,
    format TEXT,
    access_method TEXT, -- 'download', 'query', 'streaming'
    galaxy_library_path TEXT,
    last_updated TIMESTAMP
);

-- New table for database APIs
CREATE TABLE database_apis (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_name TEXT UNIQUE,
    database_name TEXT,
    description TEXT,
    biomni_module TEXT, -- e.g., 'biomni.tool.database'
    requires_auth BOOLEAN DEFAULT 0,
    auth_env_var TEXT,
    return_formats TEXT, -- JSON array ['json', 'tabular', 'fasta']
    galaxy_tool_id TEXT,
    FOREIGN KEY (galaxy_tool_id) REFERENCES tools (id)
);
```

### 5.3 Integration Scripts Required

**Scripts to Create:**

1. `scripts/add_biomni_tools_to_db.py`
   - Parse biomni/env_desc.py library_content_dict
   - Extract tool metadata
   - Generate Galaxy tool XMLs
   - Add to galaxy_ai_tools.db

2. `scripts/add_nfcore_modules_to_db.py`
   - Parse nfcore module definitions
   - Extract parameters from main.nf and meta.yml
   - Generate Galaxy tool XMLs
   - Add to galaxy_ai_tools.db

3. `scripts/setup_data_lakes.py`
   - Create Galaxy Data Library structure
   - Upload/link data lake files
   - Populate data_lakes table
   - Create "Load Dataset" tools

4. `scripts/create_database_api_tools.py`
   - Generate 31 Galaxy tools for database APIs
   - Create Python wrappers
   - Add to database_apis table

5. `scripts/rebuild_comprehensive_index.py`
   - Merge Galaxy (6295) + Biomni (161) + nfcore (98)
   - Deduplicate based on tool names
   - Rebuild FTS5 index with all tools
   - Update galaxy_tool_rag.py

---

## Part 6: Expected Outcomes

### 6.1 Tool Coverage After Integration

| Category | Galaxy Current | + Biomni | + nfcore | Total After Integration |
|----------|----------------|----------|----------|-------------------------|
| Sequence Analysis | 926 | +12 | +25 | ~963 |
| Metagenomics | 948 | +5 | +8 | ~961 |
| Proteomics | 396 | +8 | +3 | ~407 |
| RNA | 389 | +15 | +6 | ~410 |
| Metabolomics | 279 | +5 | +2 | ~286 |
| Single-Cell | ~150 | +10 | +1 | ~161 |
| Drug Discovery | ~200 | +20 | +2 | ~222 |
| Computational Chemistry | 282 | +8 | +3 | ~293 |
| **Database APIs** | 0 | **+31** | 0 | **31** |
| **Data Lakes** | Limited | **+79** | 0 | **79** |
| **TOTAL TOOLS** | **6,295** | **+161** | **+98** | **~6,500** |

### 6.2 Unique Capabilities Added

**New Workflow Types Enabled:**

1. **Whole Slide Imaging** - lazyslide integration
2. **Drug-Target Interaction ML** - deeppurpose, pytdc
3. **Single-Cell Multi-omics** - scanpy, scvelo, mudata
4. **Metabolic Modeling** - cobra, python-libsbml
5. **Gene Regulatory Networks** - pyscenic, arboreto
6. **Molecular Docking** - vina, ADFR, autosite
7. **Long-Read Sequencing** - lima, pbccs, hifiasm, clair3
8. **Clinical Data Mining** - query_clinicaltrials, query_synapse
9. **Drug Repurposing** - Broad Repurposing Hub data lake
10. **CRISPR Screen Analysis** - mageck, DepMap integration

### 6.3 Data Resource Expansion

**Before Integration:**
- Galaxy tools: 6,295
- External databases: Limited to built-in Galaxy data libraries

**After Integration:**
- Galaxy tools: ~6,500
- External databases: 31 APIs (UniProt, PDB, KEGG, GEO, cBioPortal, etc.)
- Data lakes: 79 curated datasets (BindingDB, DepMap, GTEx, MSigDB, etc.)
- Knowledge graphs: Precision medicine KG, Gene Ontology, HPO

---

## Part 7: Next Steps

### Immediate Actions (This Week)

1. **Confirm Scope with User**
   - Which priority tiers to implement first?
   - Data lake hosting strategy (Galaxy libraries vs. API)?
   - Timeline constraints?

2. **Create Tool Addition Scripts**
   - Start with `add_biomni_tools_to_db.py`
   - Parse env_desc.py and extract metadata
   - Auto-generate Galaxy XML templates

3. **Test Database API Integration**
   - Create 1-2 sample database API tools (e.g., query_uniprot)
   - Validate wrapper architecture
   - Test with Galaxy workflow

4. **Set Up Data Lake Access**
   - Identify data lake files location/download
   - Create Galaxy Data Library structure
   - Test file access and format conversion

### Questions for User

1. **Priority Order:**
   - Should we focus on biomni tools first, or nfcore modules?
   - Which specific tools are most critical for your LC-MS workflows?

2. **Data Lake Hosting:**
   - Do you have storage for 79 data lake files (~50-100 GB)?
   - Should we use Galaxy Data Libraries or create query-based tools?

3. **Database API Authentication:**
   - Which APIs require authentication tokens?
   - How should we handle API keys in Galaxy (environment variables)?

4. **Testing Requirements:**
   - Do you have sample datasets for testing new tools?
   - Which workflows should we prioritize for validation?

5. **Custom Tools (Phase 3 from Previous Work):**
   - Are the 3 external tools you mentioned related to biomni/nfcore?
   - Or are they separate custom tools?

---

## Appendices

### Appendix A: Biomni Tools NOT in Galaxy (79 tools)

**Full List from biomni_tools_unique.txt:**

```
AnnotationDbi, DADA2, DESeq2, FlowCore, GO.db, Matrix, PyMassSpec,
Rcpp, Seurat, WGCNA, arxiv, bedtools, biopandas, biopython, biotite,
biotraj, blast, blast+, blastn, blastp, blitzgsea, bowtie2, bwa,
cellpose, cellxgene-census, clusterProfiler, clusterprofile, cobra,
community, cooler, cryosparc-tools, cyvcf2, dada2, decoupler, deseq2,
devtools, diamond, dplyr, edgeR, edger, entrez-direct, faiss-cpu,
fanc, fastqc, fasttree, flowcore, flowcytometrytools, gcta, gget,
ggplot2, gsea, gseapy, harmony, harmony-pytorch, hmmlearn, homer,
igraph, impute, infernal, iqtree, iqtree2, lifelines, limma, lme4,
macs, macs2, mafft, mageck, msprime, muscle, ncbi-blast-plus,
ncbi_blast, opencv-python, openmm, plannotate, plink, plink2,
preprocessCore, pybedtools, pybigwig, pyfaidx, pykalman, pyliftover,
pymc3, pymed, pymzml, pyranges, pysam, pyscenic, pystan, pytdc,
python-libsbml, qblast, rdkit, readr, remotes, reportlab, salmon,
samtools, scanpy, scholarly, scikit-bio, scikit-image, scrublet,
scvelo, scvi, scvi-tools, segment-anything, seurat, stringr, tidyr,
trackpy, trimmomatic, trnascan-se, tskit, umap-learn, viennarna,
wgcna, xcms
```

### Appendix B: nf-core Modules NOT in Galaxy (58 modules)

**From nfcore_modules_comparison.json:**

```
md5sum, datavzrd, lima, cutesv, bclconvert, maxbin2, smoothxg, blat,
pyrodigal, prokka, smncopynumbercaller, pirate, vcfanno, trinity,
cutadapt, haplocheck, multiqc, phantompeakqualtools, clair3, spades,
unzipfiles, ampir, untar, sniffles, mosdepth, argnorm, fastavalidator,
hiphase, vcftools, quartonotebook, svync, vcf2cytosure, unzip,
toulligqc, thermorawfileparser, aria2, prinseqplusplus, trimgalore,
pychopper, checkqc, hifiasm, seq2hla, interproscan, cellpose, bioawk,
humid, megahit, sourcepredict, dupradar, pbccs, trimmomatic, upd,
nanoplot, medaka, quast, fastqc, kat
```

### Appendix C: Biomni Database API Summary

**31 Database APIs by Category:**

**Proteins & Structures (5):**
- query_uniprot, query_alphafold, query_interpro, query_pdb, query_pdb_identifiers

**Genomics & Genetics (9):**
- query_ensembl, query_ucsc, query_dbsnp, query_clinvar, query_gwas_catalog
- query_gnomad, query_regulomedb, query_geo, query_kegg

**Clinical & Pharmacology (7):**
- query_cbioportal, query_openfda, query_clinicaltrials, query_opentarget
- query_gtopdb, query_pride, query_synapse

**Pathways & Networks (3):**
- query_reactome, query_stringdb, query_remap

**Ecology & Evolution (3):**
- query_iucn, query_paleobiology, query_worms

**Regulatory & Transcription (2):**
- query_jaspar, query_remap

**Phenotypes & Diseases (2):**
- query_monarch, query_mpd, get_hpo_names

**Structural Biology (1):**
- query_emdb

---

**Document End**

*Generated: 2025-10-09*
*For: Biomate Platform Comprehensive Integration*
*Contact: Review with project team before proceeding with implementation*
