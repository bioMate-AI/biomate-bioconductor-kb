# Biomni Galaxy Tool Index - Complete Documentation

**Date**: December 1, 2025, 21:10 UTC
**Author**: Claude Code (automated generation)
**Status**: Complete

---

## Executive Summary

This document describes the complete restructuring of Biomni tools for Galaxy compatibility. The previous incorrect structure (271 XMLs for Biomni functions) has been replaced with a proper Galaxy-compatible architecture that separates atomic tool-functions (XML wrappers) from multi-step workflows (.ga files).

---

## Key Definitions

### Tool-Function (Atomic Tool)
An **atomic tool-function** is the smallest executable unit in the system. It represents a single call to an external library, package, or command-line tool.

- **Examples**: `SeqIO.read()`, `samtools view`, `DESeq()`
- **Galaxy representation**: XML wrapper file
- **Location**: `biomni_galaxy/tools/`

### Biomni Function (Workflow)
A **Biomni function** is a higher-level function defined in the Biomni codebase that orchestrates one or more tool-functions to accomplish a biological analysis task.

- **Examples**: `annotate_sc_adata()`, `run_differential_expression()`, `predict_protein_structure()`
- **Galaxy representation**: `.ga` workflow file
- **Location**: `biomni_galaxy/workflows/`

### Tool Types

| Type | Description | Wrapper |
|------|-------------|---------|
| **Python** | Python library function calls (Bio, scanpy, cv2, etc.) | `<command>python3 << 'EOF' ... EOF</command>` |
| **R** | R package function calls (DESeq2, Seurat, ggplot2, etc.) | `<command>Rscript << 'EOF' ... EOF</command>` |
| **CLI** | Command-line tool invocations (bwa, samtools, etc.) | `<command>tool_name $args</command>` |

---

## Statistics

### Tool-Functions (Atomic Tools) - 241 Total

| Tool Type | Count | Percentage |
|-----------|-------|------------|
| Python library functions | 109 | 45.2% |
| R package functions | 58 | 24.1% |
| CLI tool commands | 74 | 30.7% |
| **Total** | **241** | **100%** |

### Biomni Workflows - 122 Total

| Workflow Type | Count | Percentage |
|---------------|-------|------------|
| Multi-step (2+ tool calls) | 82 | 67.2% |
| Single-step (0-1 tool calls) | 40 | 32.8% |
| **Total** | **122** | **100%** |

---

## Python Libraries (109 functions)

### Biopython (Bio)
- SeqIO.read, SeqIO.write, SeqIO.parse
- Seq, SeqRecord
- Align.PairwiseAligner
- Blast.NCBIWWW.qblast

### Scanpy (scanpy)
- pp.normalize_total, pp.log1p, pp.highly_variable_genes
- pp.pca, pp.neighbors, pp.scale
- tl.umap, tl.leiden, tl.rank_genes_groups
- pl.umap, pl.violin, pl.dotplot

### OpenCV (cv2)
- imread, imwrite, cvtColor
- threshold, adaptiveThreshold
- findContours, drawContours
- GaussianBlur, medianBlur

### scikit-image (skimage)
- filters.threshold_otsu
- measure.label, measure.regionprops
- morphology.remove_small_objects
- segmentation.watershed

### RDKit (rdkit)
- Chem.MolFromSmiles, Chem.MolToSmiles
- Chem.Draw.MolToImage
- Descriptors.MolWt
- AllChem.GetMorganFingerprintAsBitVect

### COBRApy (cobra)
- io.read_sbml_model
- flux_analysis.flux_variability_analysis
- Model.optimize

### gget
- gget.search, gget.info
- gget.seq, gget.enrichr

### PyTorch (torch)
- torch.load, torch.save
- nn.Module, nn.Linear
- optim.Adam

### Other Python Libraries
- pandas (DataFrame, read_csv, merge)
- numpy (array, mean, std)
- scipy (stats.ttest_ind, optimize.minimize)
- matplotlib (pyplot.plot, pyplot.savefig)
- networkx (Graph, shortest_path)

---

## R Packages (58 functions)

### DESeq2 (12 functions)
- DESeqDataSetFromMatrix
- DESeq
- results
- plotMA
- plotPCA
- vst
- rlog
- counts
- normalizationFactors
- estimateSizeFactors
- estimateDispersions
- nbinomWaldTest

### edgeR (8 functions)
- DGEList
- calcNormFactors
- estimateDisp
- estimateGLMCommonDisp
- estimateGLMTrendedDisp
- glmFit
- glmLRT
- topTags

### limma (6 functions)
- lmFit
- eBayes
- topTable
- voom
- makeContrasts
- contrasts.fit

### Seurat (10 functions)
- CreateSeuratObject
- NormalizeData
- FindVariableFeatures
- ScaleData
- RunPCA
- FindNeighbors
- FindClusters
- RunUMAP
- FindAllMarkers
- DimPlot

### clusterProfiler (6 functions)
- enrichGO
- enrichKEGG
- enrichPathway
- gseGO
- gseKEGG
- dotplot

### WGCNA (6 functions)
- pickSoftThreshold
- blockwiseModules
- moduleEigengenes
- moduleTraitCor
- plotDendroAndColors
- exportNetworkToCytoscape

### ggplot2 (6 functions)
- ggplot
- geom_point
- geom_line
- geom_bar
- theme
- ggsave

### dplyr (4 functions)
- filter
- select
- mutate
- summarize

---

## CLI Tools (74 commands)

### Alignment Tools
| Tool | Commands |
|------|----------|
| bwa | mem, index, aln, samse, sampe |
| bowtie2 | bowtie2, bowtie2-build |
| hisat2 | hisat2, hisat2-build |
| star | STAR (genomeGenerate, alignReads) |
| minimap2 | minimap2 |

### SAM/BAM Processing
| Tool | Commands |
|------|----------|
| samtools | view, sort, index, flagstat, stats, merge, mpileup |
| bcftools | call, filter, view, stats, merge |
| bedtools | intersect, merge, genomecov, closest |

### Variant Calling
| Tool | Commands |
|------|----------|
| gatk | HaplotypeCaller, BaseRecalibrator, ApplyBQSR |
| mutect2 | Mutect2 |
| freebayes | freebayes |
| deepvariant | run_deepvariant |

### RNA-seq
| Tool | Commands |
|------|----------|
| salmon | index, quant |
| kallisto | index, quant |
| rsem | rsem-calculate-expression |
| htseq-count | htseq-count |
| featurecounts | featureCounts |
| stringtie | stringtie |

### QC and Trimming
| Tool | Commands |
|------|----------|
| fastqc | fastqc |
| multiqc | multiqc |
| trimmomatic | trimmomatic |
| cutadapt | cutadapt |
| fastp | fastp |

### Peak Calling
| Tool | Commands |
|------|----------|
| macs2 | callpeak, bdgcmp |
| macs3 | callpeak |
| homer | findPeaks, annotatePeaks.pl |

### Sequence Search
| Tool | Commands |
|------|----------|
| blast | blastn, blastp, blastx, makeblastdb |
| mmseqs | createdb, search, cluster |
| foldseek | createdb, search, easy-search |

### Structure Prediction
| Tool | Commands |
|------|----------|
| alphafold | run_alphafold |
| colabfold | colabfold_batch |
| esmfold | esmfold |

### Assembly
| Tool | Commands |
|------|----------|
| spades | spades.py |
| megahit | megahit |
| trinity | Trinity |

### Annotation
| Tool | Commands |
|------|----------|
| prokka | prokka |
| bakta | bakta |
| interproscan | interproscan.sh |

---

## Directory Structure

```
biomni_galaxy/
├── tools/                           # 241 XML wrappers
│   ├── python/                      # 109 Python functions
│   │   ├── bio/                     # Biopython
│   │   │   ├── seqio_read.xml
│   │   │   ├── seqio_write.xml
│   │   │   └── ...
│   │   ├── scanpy/                  # Scanpy
│   │   │   ├── pp_normalize_total.xml
│   │   │   ├── tl_umap.xml
│   │   │   └── ...
│   │   ├── cv2/                     # OpenCV
│   │   ├── skimage/                 # scikit-image
│   │   ├── rdkit/                   # RDKit
│   │   ├── cobra/                   # COBRApy
│   │   ├── gget/                    # gget
│   │   ├── pandas/                  # pandas
│   │   ├── scipy/                   # SciPy
│   │   └── torch/                   # PyTorch
│   │
│   ├── r/                           # 58 R functions
│   │   ├── deseq2/                  # DESeq2
│   │   │   ├── deseq.xml
│   │   │   ├── results.xml
│   │   │   └── ...
│   │   ├── edger/                   # edgeR
│   │   ├── limma/                   # limma
│   │   ├── seurat/                  # Seurat
│   │   ├── clusterprofiler/         # clusterProfiler
│   │   ├── wgcna/                   # WGCNA
│   │   ├── ggplot2/                 # ggplot2
│   │   ├── dplyr/                   # dplyr
│   │   └── harmony/                 # Harmony
│   │
│   └── cli/                         # 74 CLI tools
│       ├── bwa/                     # BWA
│       │   ├── mem.xml
│       │   ├── index.xml
│       │   └── ...
│       ├── samtools/                # SAMtools
│       ├── bcftools/                # BCFtools
│       ├── bedtools/                # BEDTools
│       ├── gatk/                    # GATK
│       ├── salmon/                  # Salmon
│       ├── kallisto/                # Kallisto
│       ├── fastqc/                  # FastQC
│       ├── macs2/                   # MACS2
│       ├── blast/                   # BLAST
│       ├── mmseqs/                  # MMseqs2
│       ├── foldseek/                # Foldseek
│       └── ...
│
├── workflows/                       # 122 .ga workflow files
│   ├── genomics/                    # 28 workflows
│   │   ├── analyze_genomic_region_overlap.ga
│   │   ├── annotate_variants.ga
│   │   └── ...
│   ├── bioimaging/                  # 15 workflows
│   ├── biochemistry/                # 12 workflows
│   ├── cell_biology/                # 10 workflows
│   ├── cancer_biology/              # 8 workflows
│   ├── immunology/                  # 8 workflows
│   ├── genetics/                    # 7 workflows
│   ├── molecular_biology/           # 7 workflows
│   ├── pharmacology/                # 6 workflows
│   ├── microbiology/                # 5 workflows
│   ├── synthetic_biology/           # 4 workflows
│   ├── pathology/                   # 4 workflows
│   ├── physiology/                  # 3 workflows
│   ├── biophysics/                  # 2 workflows
│   ├── bioengineering/              # 2 workflows
│   └── glycoengineering/            # 1 workflow
│
├── subworkflows/                    # Reusable workflow components
│
└── docker/                          # Docker configuration
    └── Dockerfile
```

---

## Database Schema

### Database: `biomni_tools_v2.db`

```sql
-- Atomic tool-functions (241 entries)
CREATE TABLE tool_functions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT UNIQUE NOT NULL,        -- e.g., "python/bio/SeqIO.read"
    name TEXT NOT NULL,                   -- Human-readable name
    tool_type TEXT NOT NULL,              -- 'python', 'r', 'cli'
    library TEXT NOT NULL,                -- e.g., 'biopython', 'deseq2', 'samtools'
    function TEXT NOT NULL,               -- e.g., 'SeqIO.read', 'DESeq', 'view'
    description TEXT,
    implementation TEXT,                  -- JSON with call template
    xml_path TEXT,                        -- Path to XML wrapper
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Biomni workflows (122 entries)
CREATE TABLE biomni_workflows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_id TEXT UNIQUE NOT NULL,     -- e.g., "biomni/genomics/annotate_sc_adata"
    name TEXT NOT NULL,
    domain TEXT NOT NULL,                 -- e.g., 'genomics', 'bioimaging'
    description TEXT,
    tool_calls TEXT,                      -- JSON list of tool_function IDs
    is_multi_step BOOLEAN DEFAULT FALSE,
    ga_path TEXT,                         -- Path to .ga file
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for fast lookup
CREATE INDEX idx_tool_type ON tool_functions(tool_type);
CREATE INDEX idx_library ON tool_functions(library);
CREATE INDEX idx_domain ON biomni_workflows(domain);
CREATE INDEX idx_multi_step ON biomni_workflows(is_multi_step);
```

---

## Implementation Details

### XML Wrapper Template (Python)

```xml
<?xml version="1.0" ?>
<tool id="python_bio_SeqIO_read" name="Biopython: SeqIO.read" version="1.0.0">
  <description>Read a single sequence from a file</description>
  <requirements>
    <requirement type="package" version="">biopython</requirement>
  </requirements>
  <command detect_errors="exit_code"><![CDATA[
python3 << 'EOF'
from Bio import SeqIO

# Read input
record = SeqIO.read("${input_file}", "${format}")

# Write output
SeqIO.write(record, "${output}", "${output_format}")
EOF
]]></command>
  <inputs>
    <param name="input_file" type="data" format="fasta,genbank,fastq" label="Input file"/>
    <param name="format" type="select" label="Input format">
      <option value="fasta">FASTA</option>
      <option value="genbank">GenBank</option>
      <option value="fastq">FASTQ</option>
    </param>
    <param name="output_format" type="select" label="Output format">
      <option value="fasta">FASTA</option>
      <option value="genbank">GenBank</option>
    </param>
  </inputs>
  <outputs>
    <data name="output" format="fasta" label="${tool.name} on ${on_string}"/>
  </outputs>
  <help><![CDATA[
**Biopython: SeqIO.read**

Reads a single sequence record from a file.

**Tool Type**: python
**Library**: Bio (Biopython)
**Function**: SeqIO.read
]]></help>
</tool>
```

### XML Wrapper Template (R)

```xml
<?xml version="1.0" ?>
<tool id="r_deseq2_DESeq" name="DESeq2: DESeq" version="1.0.0">
  <description>Run DESeq2 differential expression analysis</description>
  <requirements>
    <requirement type="package" version="">bioconductor-deseq2</requirement>
  </requirements>
  <command detect_errors="exit_code"><![CDATA[
Rscript << 'EOF'
library(DESeq2)

# Load data
dds <- readRDS("${input_dds}")

# Run DESeq
dds <- DESeq(dds)

# Save result
saveRDS(dds, "${output}")
EOF
]]></command>
  <inputs>
    <param name="input_dds" type="data" format="rds" label="DESeqDataSet object"/>
  </inputs>
  <outputs>
    <data name="output" format="rds" label="${tool.name} on ${on_string}"/>
  </outputs>
</tool>
```

### XML Wrapper Template (CLI)

```xml
<?xml version="1.0" ?>
<tool id="cli_samtools_view" name="SAMtools: view" version="1.0.0">
  <description>View and convert SAM/BAM files</description>
  <requirements>
    <requirement type="package" version="">samtools</requirement>
  </requirements>
  <command detect_errors="exit_code"><![CDATA[
samtools view
  #if $output_format == "bam"
    -b
  #end if
  #if $include_header
    -h
  #end if
  -o "${output}"
  "${input_file}"
]]></command>
  <inputs>
    <param name="input_file" type="data" format="sam,bam" label="Input SAM/BAM file"/>
    <param name="output_format" type="select" label="Output format">
      <option value="sam">SAM</option>
      <option value="bam">BAM</option>
    </param>
    <param name="include_header" type="boolean" label="Include header"/>
  </inputs>
  <outputs>
    <data name="output" format="bam" label="${tool.name} on ${on_string}"/>
  </outputs>
</tool>
```

### Workflow File Template (.ga)

```json
{
  "a_galaxy_workflow": "true",
  "format-version": "0.1",
  "name": "biomni_genomics_analyze_genomic_region_overlap",
  "annotation": "Analyze overlaps between two or more sets of genomic regions.",
  "tags": ["biomni", "genomics", "multi-step"],
  "steps": {
    "0": {
      "id": 0,
      "type": "data_input",
      "label": "Input: region_sets",
      "position": {"left": 0, "top": 0}
    },
    "1": {
      "id": 1,
      "type": "tool",
      "tool_id": "cli_bedtools_intersect",
      "label": "Step 1: Find intersections",
      "position": {"left": 300, "top": 50},
      "input_connections": {
        "input_a": {"id": 0, "output_name": "output"}
      }
    },
    "2": {
      "id": 2,
      "type": "tool",
      "tool_id": "python_pandas_DataFrame",
      "label": "Step 2: Create summary table",
      "position": {"left": 600, "top": 50},
      "input_connections": {
        "input": {"id": 1, "output_name": "output"}
      }
    },
    "3": {
      "id": 3,
      "type": "data_output",
      "label": "Output",
      "position": {"left": 900, "top": 50},
      "input_connections": {
        "input": {"id": 2, "output_name": "output"}
      }
    }
  },
  "workflow_outputs": [
    {
      "label": "Result",
      "output_name": "output",
      "uuid": "analyze_genomic_region_overlap-output"
    }
  ]
}
```

---

## Workflows by Domain

| Domain | Count | Notable Workflows |
|--------|-------|-------------------|
| genomics | 28 | variant_calling, rna_seq_analysis, chip_seq_pipeline |
| bioimaging | 15 | cell_segmentation, fluorescence_analysis, image_registration |
| biochemistry | 12 | enzyme_kinetics, metabolic_modeling, protein_quantification |
| cell_biology | 10 | cell_cycle_analysis, organelle_detection, migration_tracking |
| cancer_biology | 8 | tumor_mutation_burden, copy_number_analysis, pathway_enrichment |
| immunology | 8 | immune_repertoire, cytokine_profiling, t_cell_analysis |
| genetics | 7 | gwas_analysis, linkage_disequilibrium, population_genetics |
| molecular_biology | 7 | cloning_design, primer_design, expression_analysis |
| pharmacology | 6 | drug_response, dose_response, target_identification |
| microbiology | 5 | metagenomics, 16s_analysis, antimicrobial_resistance |
| synthetic_biology | 4 | circuit_design, part_characterization, chassis_optimization |
| pathology | 4 | histology_analysis, disease_classification, biomarker_detection |
| physiology | 3 | signal_processing, homeostasis_modeling, organ_function |
| biophysics | 2 | molecular_dynamics, binding_affinity |
| bioengineering | 2 | bioreactor_optimization, tissue_engineering |
| glycoengineering | 1 | glycan_analysis |

---

## Files Generated

| File Type | Count | Location |
|-----------|-------|----------|
| XML wrappers | 241 | `biomni_galaxy/tools/` |
| .ga workflows | 122 | `biomni_galaxy/workflows/` |
| SQLite database | 1 | `biomni_tools_v2.db` |
| Indexer script | 1 | `scripts/index_biomni_comprehensive.py` |

---

## Next Steps

1. **Validate XML wrappers**: Test each tool wrapper with Galaxy's planemo tool
2. **Update tool_conf.xml**: Register all new tools with Galaxy
3. **Docker image rebuild**: Update Dockerfile to include new structure
4. **Integration testing**: Run end-to-end tests with sample data
5. **Documentation**: Generate user-facing documentation for each tool

---

## Change Log

| Date | Change |
|------|--------|
| 2025-12-01 21:06 | Created tools_v2/ with 241 XML wrappers |
| 2025-12-01 21:06 | Created workflows/ with 122 .ga files |
| 2025-12-01 21:06 | Created biomni_tools_v2.db database |
| 2025-12-01 21:09 | Replaced old tools/ (271 incorrect XMLs) with new structure |
| 2025-12-01 21:10 | Documentation complete |

---

*Generated by Claude Code on December 1, 2025*
