# Omics Platform Integration Resources for bioMate
## Beyond OpenELIS: Spatial, Proteomics, Long-Read, and Multi-Omics

**Document Created:** 2025-10-28
**Purpose:** Comprehensive resource list for integrating omics platforms that OpenELIS doesn't cover
**Context:** OpenELIS handles clinical lab analyzers (12 instruments). These resources fill the gaps for research-grade omics platforms.

---

## Table of Contents

1. [Spatial Transcriptomics Integration](#1-spatial-transcriptomics-integration)
2. [Proteomics/Mass Spectrometry Integration](#2-proteomicsmass-spectrometry-integration)
3. [Long-Read Sequencing Integration](#3-long-read-sequencing-integration)
4. [NGS/Microbiome Integration](#4-ngsmicrobiome-integration)
5. [Multi-Omics Data Formats & Standards](#5-multi-omics-data-formats--standards)
6. [Cloud Infrastructure & Workflow Orchestration](#6-cloud-infrastructure--workflow-orchestration)
7. [Integration Architecture Summary](#7-integration-architecture-summary)

---

## 1. Spatial Transcriptomics Integration

### 1.1 Vendor Partnership Programs

#### **10x Genomics Compatible Partner Program (CPP)**

**Purpose:** Validates software/informatics compatibility with 10x products without requiring instrument ownership

**Contact:**
- Website: https://www.10xgenomics.com/contact/partnership
- Email: partnering@10xgenomics.com
- Application process: Partnership contact form

**Benefits:**
- Co-validation of compatibility
- Co-marketing opportunities
- Inclusion in partner directory
- Access to 10x's global customer base
- No instrument ownership required

**Platforms Covered:**
- Chromium Single Cell (scRNA-seq, scATAC-seq, Multiome)
- Visium & Visium HD (spatial transcriptomics)
- Xenium (in situ spatial)

**Recent Partners (2022-2023):**
- Element Biosciences (sequencing)
- Singular Genomics (sequencing)
- Jumpcode Genomics (sample prep)

**Key Integration Points:**
- Parse Space Ranger output (H5AD, AnnData, MEX format, .cloupe files)
- Use Cell Ranger/Space Ranger free command-line tools
- Free downloadable pipelines with standardized outputs

---

### 1.2 File Format Parsers & Libraries

#### **AnnData/H5AD Format (Standard for Spatial Data)**

**Python:**
- **anndata** - Official library (v0.13.0+)
  - `anndata.io.read_h5ad()` - Read .h5ad files
  - Website: https://anndata.readthedocs.io
  - GitHub: https://github.com/scverse/anndata

- **scanpy** - Built on anndata
  - `scanpy.read_h5ad()` - Load with backed mode support
  - Website: https://scanpy.readthedocs.io
  - Full integration with spatial transcriptomics

**R:**
- **anndataR** - R wrapper for H5AD
  - Website: https://anndatar.data-intuitive.com
  - Functions: `read_h5ad()`, `write_h5ad()`

- **anndata (R version)** - CRAN package
  - Updated June 2025
  - Documentation: https://rdrr.io/cran/anndata/

**Format Details:**
- Hierarchical storage: HDF5 (H5py) and Zarr
- Sparse matrix support: CSC and CSR formats
- Three 1D arrays: indptr, indices, data

---

### 1.3 Galaxy Tool Wrappers

#### **SPOC: Galaxy Single-cell & Spatial Omics Community**

**Resources:**
- Website: https://galaxyproject.org/community/sig/singlecell/
- Tools: 175+ tools for single-cell and spatial analysis
- Training: 120+ training resources
- Usage: 300,000+ jobs running

**Key Tools:**
- **Scanpy** (Python-based scRNA-seq/spatial)
- **Seurat** (R-based scRNA-seq/spatial)
- **SC3, Scater** (R-based alternatives)

**Latest Development (2025):**
- MIGHTS (Multi-Interface Galaxy Hands-on Training Suite)
- Parallel analytical methods: GUI + code
- Smooth transitions between Scanpy and Seurat

**Repository:**
- GitHub: https://github.com/galaxyproject/tools-iuc
- Category: "Transcriptomics"

---

### 1.4 Bioconductor Packages

#### **Spatial Visualization & Analysis**

**ggsc** (Updated October 2025 - v1.7.1)
- Visualize single-cell and spatial data
- Supports: Seurat, SingleCellExperiment, SpatialExperiment
- Grammar of graphics (ggplot2 syntax)
- Website: https://new.bioconductor.org/packages/ggsc

**spatialLIBD**
- Interactive exploration of 10x Visium data
- Web application + R package
- Alternative to Loupe Browser
- Website: https://research.libd.org/spatialLIBD/
- Publication: BMC Genomics 2022

**SpatialCPie**
- Cluster evaluation for spatial transcriptomics
- Shiny gadget for interactive UI
- Parallel plot exploration
- Website: https://bioconductor.org/packages/SpatialCPie

**SpatialExperiment**
- Core infrastructure for spatial data in R
- Foundation for other packages
- PMC: https://pmc.ncbi.nlm.nih.gov/articles/PMC9154247/

---

### 1.5 Nextflow/nf-core Pipelines

**nf-core/spatialvi**
- Purpose: Visium spatial transcriptomics (10x Genomics)
- Capabilities:
  - Process raw data by running Space Ranger
  - Analyze pre-processed Space Ranger outputs
- GitHub: https://github.com/nf-core/spatialvi
- Website: https://nf-co.re/spatialvi/

**nf-core/sopa**
- Purpose: Technology-invariant spatial omics
- Built on SpatialData framework
- Image-based spatial omics with single-cell resolution
- Website: https://nf-co.re/sopa/

**btc-spatial-pipelines**
- Nextflow spatial pipelines (Break Through Cancer)
- Covers: Spatial Transcriptomics, IMC, etc.
- GitHub: https://github.com/break-through-cancer/btc-spatial-pipelines

---

## 2. Proteomics/Mass Spectrometry Integration

### 2.1 File Format Conversion

#### **ProteoWizard msConvert** (Industry Standard)

**Purpose:** Convert vendor RAW files to open formats (mzML, mzXML)

**Supported Vendors:**
- AB SCIEX
- Agilent
- Bruker
- Shimadzu
- Thermo Scientific
- Waters

**Tools:**
- **msconvert** - Command-line tool
- **msConvertGUI** - Windows GUI version

**Download:**
- Website: https://proteowizard.sourceforge.io/
- Documentation: https://proteowizard.sourceforge.io/tools/msconvert.html

**Platform:** Windows only (vendor restrictions)

**Example Usage:**
```bash
msconvert raw_data_file.RAW --filter "peakPicking true 1-"
```

**Key Features:**
- Converts to mzML, mzData, mzXML
- Peak picking filters
- Compression options
- Batch processing

---

### 2.2 mzML Parsing Libraries

#### **Python Libraries**

**Pyteomics** (Comprehensive)
- Full proteomics toolkit
- mzML iterative parsing
- Indexed access support
- Schema reading
- Website: https://pyteomics.readthedocs.io
- Publication: J. Proteome Research 2019

**pymzML**
- Fast mzML parser
- Python 2.6.5+ and Python 3 compatible
- Competes with C/C++ performance
- GitHub: https://github.com/pymzml/pymzML
- Publication: Bioinformatics 2012

**psims**
- Declarative writer for mzML and mzIdentML
- XML stream management
- Referential integrity
- PMC: https://pmc.ncbi.nlm.nih.gov/articles/PMC6398200/

**pyOpenMS**
- High-performance C++ API with Python bindings
- Indexed mzML support
- Low-memory random access
- Event-driven sequential access

#### **Java Libraries**

**jmzML**
- Official PSI mzML Java API
- Handle large files in minimal memory
- PubMed: https://pubmed.ncbi.nlm.nih.gov/20127693/

**dp-mzml**
- Fast spectrum parsing
- Sequential iteration or random access
- GitHub: https://github.com/digitalproteomics/dp-mzml

---

### 2.3 Galaxy Tools for Proteomics

**MaxQuant Integration:**
- Docker: `biocontainers/maxquant:v1.6.17`
- Label-free quantification
- FDR control <1%
- RAW file processing

**Skyline:**
- Targeted proteomics
- Free, open-source
- Website: https://skyline.ms

**MS-DIAL 5:**
- AI-powered deconvolution
- Metabolomics + Lipidomics
- Website: http://prime.psc.riken.jp/compms/msdial/

**MSFragger:**
- Ultra-fast peptide identification
- Large dataset handling

---

### 2.4 Nextflow/nf-core Pipelines

**nf-core/mhcquant**
- Quantitative peptidomics
- Data-dependent processing
- Applications: proteomics, immunopeptidomics
- Website: https://nf-co.re/mhcquant

---

## 3. Long-Read Sequencing Integration

### 3.1 Vendor Partnership Programs

#### **Oxford Nanopore Compatible Products Programme**

**Launch:** May 2024 (expanded April 2025)

**New Partners (2025 Cohort):**
- 10x Genomics
- Agilent Technologies
- Asuragen
- Day Zero Diagnostics
- Hamilton Robotics
- New England Biolabs (NEB)
- Opentrons
- Pathosense
- Thermo Fisher Scientific

**Benefits:**
- Rigorous validation process
- Access to 125+ country user base
- Shared customer base
- Joint product announcements

**Contact:**
- Website: https://nanoporetech.com/about/partners/nanopore-compatible-products-programme

**API Access:**
- **MinKNOW API** (gRPC-based)
- GitHub: https://github.com/nanoporetech/minknow_api
- Python modules available
- Supports: Go, Java, Ruby, JavaScript, etc.
- Fixed API per minor MinKNOW release

**Integration Points:**
- Connect upstream/downstream tools
- LIMS integration
- Automated workflow triggers

---

#### **PacBio Technology Partner Program**

**SMRT Link Software (v25.2):**
- Recommended for Revio and Vega systems
- Design runs
- Monitor sequencing
- Review performance metrics
- Analyze, visualize, annotate data

**SMRT Link Web Services API:**
- Query new data from instrument
- Start secondary analyses
- Integration with third-party software

**Documentation:**
- Website: https://www.pacb.com/support/documentation/
- User Guide: https://www.pacb.com/wp-content/uploads/SMRT-Link-User-Guide-v25.1.pdf
- Installation Guide: https://www.pacb.com/wp-content/uploads/SMRT-Link-software-installation-guide-v25.1.pdf

**PacBio Compatible Program:**
- Connects with best-in-class bioinformatics
- Partnerships with platforms, tool developers, cloud providers

---

### 3.2 File Format Parsers

#### **BAM/FASTQ Parsing**

**minimap2** (Primary Aligner)
- Supports gzip'd FASTA and FASTQ
- Output: BAM files
- Ultra-long read support with `-L` flag (moves long CIGAR to CG tag)
- GitHub: https://github.com/lh3/minimap2

**Important for Ultra-Long Reads:**
- BAM limitation: CIGAR strings >65,535 operations fail
- Solution: Use `-L` flag to avoid CIGAR overflow
- ~1% of ultra-long nanopore reads affected

**Galaxy Integration:**
- Available in Galaxy toolshed
- Paired-end collection support
- Various presets: `-x sr`, `-x map-ont`, `-x map-pb`

**Workflow Tools:**
- `samtools fixmate` - Fix mate pairs
- `samtools sort` - Sort alignments
- `samtools markdup` - Mark duplicates
- Output to CRAM for space efficiency

**Example Pipeline:**
```bash
minimap2 -t 8 -a -x sr reference.fa reads_[12].fastq | \
  samtools fixmate -u -m - - | \
  samtools sort -u -@2 -T /tmp/prefix - | \
  samtools markdup -@8 --reference reference.fa - final.cram
```

---

### 3.3 Variant Calling Tools

**ONT Variant Callers:**
- **Clair3** - Optimized for ONT R10 chemistry
- **Pepper-Margin-DeepVariant** - Google's deep learning approach
- **Medaka** - ONT's official caller

**PacBio Variant Callers:**
- **DeepVariant** - Recommended for HiFi
- **pbsv** - Structural variant calling
- **pbmm2** - PacBio-optimized minimap2

**Structural Variant Callers:**
- **Sniffles2** - Multi-sample SV calling
- **CuteSV** - Fast SV detection
- **SVIM** - SV identification from alignments
- **NanoSV** - Nanopore-specific

---

## 4. NGS/Microbiome Integration

### 4.1 QIIME 2 Galaxy Integration

**Current Version:** 2025.4.0 (installed on Galaxy)

**q2Galaxy:**
- Generates Galaxy tools from QIIME 2 actions
- GitHub: https://github.com/qiime2/q2galaxy
- Docker images: quay.io/repository/qiime2/q2galaxy

**Official Galaxy Tools:**
- GitHub: https://github.com/qiime2/galaxy-tools
- Category: Metagenomics

**Key Tutorial:**
- "Moving Pictures tutorial - Microbiome marker gene analysis with QIIME 2"
- 16S amplicon analysis on Galaxy
- Galaxy Community Hub: https://galaxyproject.org/use/qiime2/

**Documentation:**
- Supports multiple interfaces: Galaxy, CLI, Python API, R API
- Website: https://docs.qiime2.org

**Example Workflows:**
- ASaiM - QIIME - Illumina Overview
- Published at: https://usegalaxy.eu/u/berenice/w/asaim-qiime-illumina-overview-tutorial

---

### 4.2 QIIME 2 Analysis Capabilities

**Data Types:**
- 16S/18S rRNA amplicon sequencing
- ITS (fungal) sequencing
- Shotgun metagenomics
- Metabolomics (in development)

**Workflow Steps:**
1. Import FASTQ to QIIME 2 artifacts (.qza)
2. Quality control (DADA2/Deblur denoising)
3. Feature table (ASV generation)
4. Taxonomy assignment (SILVA, Greengenes, RDP)
5. Diversity analysis (alpha/beta diversity)
6. Differential abundance (ANCOM, ALDEx2)
7. Interactive visualization

**Reference Databases:**
- **SILVA** - Most comprehensive
- **Greengenes** - Legacy, still used
- **RDP** - Ribosomal Database Project

---

## 5. Multi-Omics Data Formats & Standards

### 5.1 Sequencing Data Formats

**Primary Formats:**
- **FASTQ** - Raw sequence reads + quality scores
- **BAM/CRAM** - Aligned sequence data (binary)
- **SAM** - Aligned sequence data (text)
- **VCF/BCF** - Variant calls

**Spatial Formats:**
- **H5AD** - AnnData HDF5 (Python/R standard)
- **MEX** - Market Exchange format (10x)
- **.cloupe** - 10x Loupe Browser format

**Proteomics Formats:**
- **mzML** - Universal mass spectrometry (XML)
- **mzTab** - Results tables
- **mzIdentML** - Peptide/protein identifications
- **RAW** - Vendor-specific (Thermo, etc.)

**Imaging Formats:**
- **OME-TIFF** - Open Microscopy Environment
- **DICOM** - Medical imaging standard

---

### 5.2 Metadata Standards

**MIAME** - Microarray
**MIAPE** - Proteomics
**MINSEQE** - Sequencing
**ISA-Tab** - General investigation/study/assay

**Clinical Standards:**
- **LOINC** - Laboratory test coding
- **SNOMED CT** - Clinical terminology
- **HL7/FHIR** - Healthcare interoperability

---

## 6. Cloud Infrastructure & Workflow Orchestration

### 6.1 Nextflow/nf-core Ecosystem

**nf-core Stats (February 2025):**
- 124 pipelines available
- Data types: Sequencing, mass spec, protein structure, microscopy
- All pipelines containerized (Docker/Singularity)

**Key Pipelines for bioMate:**

**Spatial Omics:**
- `nf-core/spatialvi` - 10x Visium
- `nf-core/sopa` - Multi-platform spatial

**Proteomics:**
- `nf-core/mhcquant` - Peptidomics

**Long-Read:**
- Various community pipelines for ONT/PacBio

**Benefits:**
- Cloud-native (AWS, Azure, GCP)
- Reproducible workflows
- Extensive documentation
- Active community

**Resources:**
- Website: https://nf-co.re
- GitHub: https://github.com/orgs/nf-core/repositories
- Publication: Genome Biology 2025

---

### 6.2 Galaxy Workflow System

**Scale:**
- 300,000+ users globally
- 8,000+ tools available
- 175+ single-cell/spatial tools
- 120+ training resources

**Advantages:**
- Web-based interface
- No coding required
- Workflow sharing
- Cloud deployment support
- HIPAA-compliant options

**Resources:**
- Main site: https://galaxyproject.org
- European instance: https://usegalaxy.eu
- US instance: https://usegalaxy.org
- Training: https://training.galaxyproject.org

---

### 6.3 Container Technologies

**Docker:**
- Biocontainers: https://biocontainers.pro
- Most bioinformatics tools available
- Example: `biocontainers/maxquant:v1.6.17`

**Singularity/Apptainer:**
- HPC-friendly alternative to Docker
- Compatible with Docker images
- No root privileges needed

---

## 7. Integration Architecture Summary

### Layer 1: Clinical Lab Instruments (OpenELIS)
```
Sysmex | Cobas | GeneXpert | FACS
    ↓
OpenELIS (MPL 2.0)
    ↓
REST API → Galaxy
```

### Layer 2: Spatial Transcriptomics
```
10x Visium/Xenium | MERSCOPE | CosMx
    ↓
Space Ranger | Vendor Software
    ↓
H5AD/AnnData Format
    ↓
Scanpy/Seurat in Galaxy
    ↓
bioMate Platform
```

### Layer 3: Proteomics
```
Thermo | Waters | Bruker | Agilent
    ↓
RAW Files
    ↓
ProteoWizard msConvert
    ↓
mzML Format
    ↓
MaxQuant/MSFragger in Galaxy
    ↓
bioMate Platform
```

### Layer 4: Long-Read Sequencing
```
ONT MinION/PromethION | PacBio Revio
    ↓
FAST5/POD5 | HiFi BAM
    ↓
Basecalling → FASTQ
    ↓
minimap2 Alignment
    ↓
Variant Calling in Galaxy
    ↓
bioMate Platform
```

### Layer 5: Microbiome
```
Illumina MiSeq/NovaSeq
    ↓
FASTQ Files
    ↓
QIIME 2 in Galaxy
    ↓
16S/Shotgun Analysis
    ↓
bioMate Platform
```

---

## Quick Start Resources by Platform

### For Spatial Transcriptomics:
1. Apply to 10x CPP: partnering@10xgenomics.com
2. Install Galaxy tools: Scanpy, Seurat from tools-iuc
3. Python libraries: `pip install scanpy anndata`
4. R packages: `BiocManager::install("spatialLIBD")`

### For Proteomics:
1. Download ProteoWizard: https://proteowizard.sourceforge.io/
2. Python: `pip install pyteomics pymzml`
3. Galaxy: Install MaxQuant wrapper
4. Java: Use jmzML for enterprise integration

### For Long-Read Sequencing:
1. Apply to ONT Compatible Programme: https://nanoporetech.com/about/partners
2. Install minimap2: `conda install -c bioconda minimap2`
3. Variant callers: `conda install -c bioconda clair3 sniffles2`
4. Galaxy: Use minimap2 + variant calling tools

### For Microbiome:
1. QIIME 2 Galaxy: https://galaxyproject.org/use/qiime2/
2. Docker: `docker pull quay.io/qiime2/q2galaxy`
3. Galaxy tutorial: "Moving Pictures" on usegalaxy.org
4. Reference databases: SILVA, Greengenes (free downloads)

---

## Next Steps for bioMate Integration

### Week 1-2: Vendor Applications
- [ ] Submit 10x Genomics CPP application
- [ ] Submit ONT Compatible Products Programme application
- [ ] Contact PacBio for partnership discussion

### Week 3-4: Tool Installation
- [ ] Install Scanpy/Seurat in Galaxy
- [ ] Set up ProteoWizard conversion pipeline
- [ ] Configure minimap2 for long-read alignment
- [ ] Deploy QIIME 2 in Galaxy

### Month 2: File Format Handling
- [ ] Build H5AD parser for spatial data
- [ ] Implement mzML import for proteomics
- [ ] Configure BAM/FASTQ handling for long-read
- [ ] Test end-to-end data flow

### Month 3: Pilot Testing
- [ ] Process 10 Visium samples through pipeline
- [ ] Convert 10 RAW proteomics files to mzML
- [ ] Align 10 ONT FASTQ files
- [ ] Run QIIME 2 on 10 16S datasets

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Maintained By:** bioMate Platform Team
**Next Review:** After vendor partnership approvals
