# BioMate-KB — Bioconductor Skills

**200 Bioconductor packages — the top 100 most-downloaded plus the top 100 rising stars — formatted as Claude Code Skills.**

A skill bundle in [Claude Code Skills](https://docs.anthropic.com/en/docs/claude-code/skills-overview) format. It covers the 100 most-used Bioconductor packages **and** the top 100 rising-star packages (newly released since ~2021 and fast-growing) from the BioMate-KB knowledge base. Each skill teaches Claude when to choose a package, **the workflows it supports** (each analysis as a recipe), what parameters to set, how to interpret results, and what pitfalls to avoid.

## What's here

```
skills/   (200 packages across 12 domains)
├── transcriptomics/    (97 skills — DESeq2, edgeR, limma, crisprscore, ...)
├── genomics/           (33 skills — GenomicRanges, Rsamtools, syntenet, ...)
├── general/            (19 skills — utility / cross-domain)
├── proteomics/         (16 skills — MSstats, MSnbase, prone, ...)
├── epigenomics/        (10 skills — ChIPseeker, methylKit, HiCExperiment, ...)
├── single-cell/        (8  skills — Seurat, scran, demuxmix, ...)
├── variant-calling/    (4  skills — VariantAnnotation, maftools, ...)
├── metagenomics/       (4  skills — phyloseq, ANCOMBC, dada2, ...)
├── imaging/            (4  skills — flowCore, lisaclust, ...)
├── annotation/         (2  skills — biomaRt, AnnotationHub, ...)
├── enrichment/         (2  skills — clusterProfiler, ReactomePA, ...)
└── metabolomics/       (1  skill)
```

A package that supports multiple analyses lists each as a `### ` recipe under a **`## Workflows`** section (e.g. DESeq2 → standard / multi-factor / LRT; crisprscore → on-target / off-target / indel scoring). The most-used 100 account for ~60% of all Bioconductor downloads; the rising-star 100 surface newly-important packages before they hit the top by volume. The full BioMate KB covers all 1,818 active Bioconductor packages, available via [BioMate Cloud](https://biomate.ai).

**Bioconductor version:** these skills are grounded against **Bioconductor 3.21** (pinned explicitly — `release` is a moving pointer that drops packages as it advances, e.g. several rising stars dropped out of 3.23). The pinned version is recorded in `MANIFEST.json` (`bioconductor_version`); re-fetch a different snapshot with `BIOC_VERSION=… python3 extraction/fetch_authoritative_sources.py`.

## Full package list

All 100 packages by domain (alphabetical within each domain).

| # | Package | Domain | Description |
|---|---------|--------|-------------|
| 1 | `affy` | transcriptomics | The package contains functions for exploratory oligonucleotide array analysis. The depende… |
| 2 | `apeglm` | transcriptomics | apeglm provides Bayesian shrinkage estimators for effect sizes for a variety of GLM models… |
| 3 | `AUCell` | transcriptomics | AUCell allows to identify cells with active gene sets (e.g. signatures, gene modules...) i… |
| 4 | `batchelor` | transcriptomics | Implements a variety of methods for batch correction of single-cell (RNA sequencing) data.… |
| 5 | `dada2` | transcriptomics | The dada2 package infers exact amplicon sequence variants (ASVs) from high-throughput ampl… |
| 6 | `DESeq2` | transcriptomics | Uses DESeq2 to estimate variance-mean dependence in count data from high-throughput sequen… |
| 7 | `DropletUtils` | transcriptomics | The filtering uses intelligent methods to generate output 10X matrices as would be otherwi… |
| 8 | `edgeR` | transcriptomics | Estimates differential gene expression for short read sequence count using methods appropr… |
| 9 | `EnhancedVolcano` | transcriptomics | Volcano plots represent a useful way to visualise the results of differential expression a… |
| 10 | `fgsea` | transcriptomics | A tabular file with gene symbols in the first column, and a ranked statistic (e.g. t-stati… |
| 11 | `GEOquery` | transcriptomics | This tool fetches microarray data directly from GEO database, based on the GEOQuery R pack… |
| 12 | `glmGamPoi` | transcriptomics | Fit linear models to overdispersed count data. The package can estimate the overdispersion… |
| 13 | `GSEABase` | transcriptomics | This package provides classes and methods to support Gene Set Enrichment Analysis (GSEA). |
| 14 | `GSVA` | transcriptomics | Gene Set Variation Analysis (GSVA) is a non-parametric, unsupervised method for estimating… |
| 15 | `illuminaio` | transcriptomics | Tools for parsing Illumina's microarray output files, including IDAT. |
| 16 | `limma` | transcriptomics | Given a matrix of counts (e.g. from featureCounts) and optional information about the gene… |
| 17 | `MAST` | transcriptomics | Methods and models for handling zero-inflated single cell assay data. |
| 18 | `MetaboCoreUtils` | transcriptomics | MetaboCoreUtils defines metabolomics-related core functionality provided as low-level func… |
| 19 | `metapod` | transcriptomics | Implements a variety of methods for combining p-values in differential analyses of genome-… |
| 20 | `monocle` | transcriptomics | Monocle performs differential expression and time-series analysis for single-cell expressi… |
| 21 | `msa` | transcriptomics | The 'msa' package provides a unified R/Bioconductor interface to the multiple sequence ali… |
| 22 | `pathview` | transcriptomics | Pathview is a stand-alone software package for pathway based data integration and visualiz… |
| 23 | `scater` | transcriptomics | A collection of tools for doing various analyses of single-cell RNA-seq gene expression da… |
| 24 | `scDblFinder` | transcriptomics | The scDblFinder package gathers various methods for the detection and handling of doublets… |
| 25 | `scran` | transcriptomics | Implements miscellaneous functions for interpretation of single-cell RNA-seq data. Methods… |
| 26 | `scuttle` | transcriptomics | Provides basic utility functions for performing single-cell analyses, focusing on simple n… |
| 27 | `siggenes` | transcriptomics | Identification of differentially expressed genes and estimation of the False Discovery Rat… |
| 28 | `SingleR` | transcriptomics | Performs unbiased cell type recognition from single-cell RNA sequencing data, by leveragin… |
| 29 | `SpatialExperiment` | transcriptomics | Defines an S4 class for storing data from spatial -omics experiments. The class extends Si… |
| 30 | `sva` | transcriptomics | The sva package contains functions for removing batch effects and other unwanted variation… |
| 31 | `TrajectoryUtils` | transcriptomics | Implements low-level utilities for single-cell trajectory analysis, primarily intended for… |
| 32 | `treeio` | transcriptomics | 'treeio' is an R package to make it easier to import and store phylogenetic tree with asso… |
| 33 | `tximport` | transcriptomics | Current version only works in 'merge' mode: A single table of gene summarizations is gener… |
| 34 | `annotate` | genomics | This tool uses the label-tree function from HyPhy to annotate a phylogenetic tree. It allo… |
| 35 | `biocViews` | genomics | Infrastructure to support 'views' used to classify Bioconductor packages. 'biocViews' are … |
| 36 | `Biostrings` | genomics | Memory efficient string containers, string matching algorithms, and other utilities, for f… |
| 37 | `BSgenome` | genomics | Infrastructure shared by all the Biostrings-based genome data packages. |
| 38 | `clusterProfiler` | genomics | This package supports functional characteristics of both coding and non-coding genomics da… |
| 39 | `ComplexHeatmap` | genomics | Complex heatmaps are efficient to visualize associations between different sources of data… |
| 40 | `ConsensusClusterPlus` | genomics | algorithm for determining cluster count and membership by stability evidence in unsupervis… |
| 41 | `DECIPHER` | genomics | A toolset for deciphering and managing biological sequences. |
| 42 | `DNAcopy` | genomics | Implements the circular binary segmentation (CBS) algorithm to segment DNA copy number dat… |
| 43 | `GenomicAlignments` | genomics | Provides efficient containers for storing and manipulating short genomic alignments (typic… |
| 44 | `GenomicFeatures` | genomics | Extract the genomic locations of genes, transcripts, exons, introns, and CDS, for the gene… |
| 45 | `GenomicRanges` | genomics | The ability to efficiently represent and manipulate genomic annotations and alignments is … |
| 46 | `ggbio` | genomics | The ggbio package extends and specializes the grammar of graphics for biological data. The… |
| 47 | `ggtree` | genomics | 'ggtree' extends the 'ggplot2' plotting system which implemented the grammar of graphics. … |
| 48 | `GOSemSim` | genomics | The semantic comparisons of Gene Ontology (GO) annotations provide quantitative ways to co… |
| 49 | `Gviz` | genomics | Genomic data analyses requires integrated visualization of known genomic information and n… |
| 50 | `KEGGREST` | genomics | A package that provides a client interface to the Kyoto Encyclopedia of Genes and Genomes … |
| 51 | `OrganismDbi` | genomics | The package enables a simple unified interface to several annotation packages each of whic… |
| 52 | `Rsamtools` | genomics | This package provides an interface to the 'samtools', 'bcftools', and 'tabix' utilities fo… |
| 53 | `rtracklayer` | genomics | Extensible framework for interacting with multiple genome browsers (currently UCSC built-i… |
| 54 | `ShortRead` | genomics | This package implements sampling, iteration, and input of FASTQ files. The package include… |
| 55 | `TFBSTools` | genomics | TFBSTools is a package for the analysis and manipulation of transcription factor binding s… |
| 56 | `txdbmaker` | genomics | A set of tools for making TxDb objects from genomic annotations from various sources (e.g.… |
| 57 | `basilisk` | general | Installs a self-contained conda instance that is managed by the R/Bioconductor installatio… |
| 58 | `Biobase` | general | Functions that are needed by many other packages or which replace R functions. |
| 59 | `biovizBase` | general | The biovizBase package is designed to provide a set of utilities, color schemes and conven… |
| 60 | `DOSE` | general | This package implements five methods proposed by Resnik, Schlicker, Jiang, Lin and Wang re… |
| 61 | `ExperimentHub` | general | This package provides a client for the Bioconductor ExperimentHub web resource. Experiment… |
| 62 | `gdsfmt` | general | Provides a high-level R interface to CoreArray Genomic Data Structure (GDS) data files. GD… |
| 63 | `genefilter` | general | Some basic functions for filtering genes. |
| 64 | `geneplotter` | general | Functions for plotting genomic data |
| 65 | `graphite` | general | Graph objects from pathway topology derived from KEGG, Panther, PathBank, PharmGKB, Reacto… |
| 66 | `gypsum` | general | Client for the gypsum REST API (https://gypsum.artifactdb.com), a cloud-based file store i… |
| 67 | `MultiAssayExperiment` | general | Harmonize data management of multiple experimental assays performed on an overlapping set … |
| 68 | `pcaMethods` | general | Provides Bayesian PCA, Probabilistic PCA, Nipals PCA, Inverse Non-Linear PCA and the conve… |
| 69 | `qvalue` | general | This package takes a list of p-values resulting from the simultaneous testing of many hypo… |
| 70 | `ResidualMatrix` | general | Provides delayed computation of a matrix of residuals after fitting a linear model to each… |
| 71 | `seqlogo` | general | seqLogo takes the position weight matrix of a DNA sequence motif and plots the correspondi… |
| 72 | `topGO` | general | topGO package provides tools for testing GO terms while accounting for the topology of the… |
| 73 | `mixOmics` | proteomics | Multivariate methods are well suited to large omics data sets where the number of variable… |
| 74 | `MsCoreUtils` | proteomics | MsCoreUtils defines low-level functions for mass spectrometry data and is independent of a… |
| 75 | `MSnbase` | proteomics | MSnbase provides infrastructure for manipulation, processing and visualisation of mass spe… |
| 76 | `mzID` | proteomics | A parser for mzIdentML files implemented using the XML package. The parser tries to be gen… |
| 77 | `mzR` | proteomics | mzR provides a unified API to the common file formats and parsers available for mass spect… |
| 78 | `PSMatch` | proteomics | The PSMatch package helps proteomics practitioners to load, handle and manage Peptide Spec… |
| 79 | `QFeatures` | proteomics | The QFeatures infrastructure enables the management and processing of quantitative feature… |
| 80 | `STRINGdb` | proteomics | tags: [bioconductor, r, proteomics, vignette-grounded] |
| 81 | `AnnotationHub` | variant-calling | This package provides a client for the Bioconductor AnnotationHub web resource. The Annota… |
| 82 | `snpStats` | variant-calling | Classes and statistical methods for large SNP association studies. This extends the earlie… |
| 83 | `VariantAnnotation` | variant-calling | Annotate variants, compute amino acid coding changes, predict coding outcomes. |
| 84 | `vsn` | variant-calling | The package implements a method for normalising microarray intensities from single- and mu… |
| 85 | `biomformat` | metagenomics | This is an R package for interfacing with the BIOM format. This package includes basic too… |
| 86 | `DirichletMultinomial` | metagenomics | Dirichlet-multinomial mixture models can be used to describe variability in microbial meta… |
| 87 | `microbiome` | metagenomics | Utilities for microbiome analysis. |
| 88 | `phyloseq` | metagenomics | phyloseq provides a set of classes and tools to facilitate the import, storage, analysis, … |
| 89 | `SingleCellExperiment` | single-cell | Defines a S4 class for storing data from single-cell experiments. This includes specialize… |
| 90 | `TreeSummarizedExperiment` | single-cell | TreeSummarizedExperiment has extended SingleCellExperiment to include hierarchical informa… |
| 91 | `zellkonverter` | single-cell | Provides methods to convert between Python AnnData objects and SingleCellExperiment object… |
| 92 | `bumphunter` | epigenomics | Tools for finding bumps in genomic data |
| 93 | `ChIPseeker` | epigenomics | ChIPseeker is a Bioconductor package for annotating ChIP-seq data analysis. Peak Annotatio… |
| 94 | `minfi` | epigenomics | Tools to analyze & visualize Illumina Infinium methylation arrays. |
| 95 | `enrichplot` | enrichment | The 'enrichplot' package implements several visualization methods for interpreting functio… |
| 96 | `ReactomePA` | enrichment | Reactome is a free, open-source, curated and peer-reviewed pathway database. Their goal is… |
| 97 | `biomaRt` | annotation | In recent years a wealth of biological data has become available in public data repositori… |
| 98 | `KEGGgraph` | annotation | KEGGGraph is an interface between KEGG pathway and graph object as well as a collection of… |
| 99 | `EBImage` | imaging | EBImage provides general purpose functionality for image processing and analysis. In the c… |
| 100 | `flowCore` | imaging | Provides S4 data structures and basic functions to deal with flow cytometry data. |

Each `SKILL.md` has:
- **YAML frontmatter**: `name`, `description`, `when_to_use`, `user-invocable: false`
- **Best Practices** — what to do and how to configure
- **Key Parameters** — recommended values with context
- **Result Interpretation** — how to read outputs
- **Common Pitfalls** — what to warn users about
- **Data Requirements** — expected input format
- **Alternatives** — when to suggest a different package

## Want the full collection?

This bundle covers the top 100 Bioconductor packages. **[BioMate AI](https://www.biomate.ai)** gives you:

- **Full coverage** — all 1,818+ active Bioconductor packages plus 2,455 curated workflows across genomics, transcriptomics, proteomics, drug discovery, and more
- **Efficient parallel computing** — workflows run in the cloud with automatic scaling, no cluster setup required
- **Output visualization and analysis** — interactive charts, QC dashboards, and AI-generated findings built in
- **Report generation** — one-click publication-ready methods reports and summary documents

**Start using BioMate AI for free at [www.biomate.ai](https://www.biomate.ai)**
Questions or collaboration inquiries: [contact@biomate.ai](mailto:contact@biomate.ai)

## How to use

```bash
# Clone
git clone https://github.com/bioMate-AI/biomate-bioconductor-kb.git
cd biomate-bioconductor-kb

# Install all skills into Claude Code (global)
find skills -name "SKILL.md" | while read f; do
  pkg=$(dirname "$f" | xargs basename)
  cp "$f" ~/.claude/skills/bioconductor-${pkg}.md
done
```

Or copy a single domain:

```bash
# Only RNA-seq DE skills
find skills/transcriptomics -name "SKILL.md" | while read f; do
  pkg=$(dirname "$f" | xargs basename)
  cp "$f" ~/.claude/skills/bioconductor-${pkg}.md
done
```

Each `SKILL.md` is a self-contained Claude Code skill file — Claude discovers it automatically once it's in `~/.claude/skills/` (global) or `.claude/skills/` (project-level).

## Ranking source

Packages are ordered by Bioconductor's official monthly download score:
- Source: <https://bioconductor.org/packages/stats/bioc/bioc_pkg_scores.tab>
- Snapshot taken: 2026-05-21
- Top 100 of 3,058 ranked Bioconductor software packages (covers 3.3% of the catalog by count, ~60% by traffic)

Because the ranking is by download volume, the bundle includes both **analysis tools** (DESeq2, edgeR, limma, fgsea, …) and the **core data-structure, I/O, and annotation packages** that nearly every analysis depends on (GenomicRanges, Biostrings, SingleCellExperiment, AnnotationHub, …) — the latter rank highly precisely because they are imported everywhere. Both are useful to an agent: the analysis packages teach *how to analyze*, the foundational ones *how to represent and load* the data.

## Knowledge layer, not pipelines

These skills are the **knowledge layer** — when and why to use each package, with parameters, assumptions, pitfalls, and alternatives. They are not runnable pipelines and carry no infrastructure details.

**BioMate hosts and executes these workflows for you** — managed compute, automated QC, and reproducible outputs — powered by this same Bioconductor know-how. For end-to-end cloud execution, see **[BioMate](https://www.biomate.ai)**.

## License

- **Skill content** (`skills/**/*.md`, `MANIFEST.json`): **CC-BY-4.0** — share + adapt with attribution.
- **Extraction scripts** (`extraction/*.py`): **Apache-2.0** — use, modify, distribute.
- **Underlying Bioconductor packages** retain their own (mostly Artistic-2.0 / GPL) licenses.

## Citation

If you use this skill bundle in research, please cite:

> Zhang, Y. (2026). *BioMate-KB: A Real-Execution-Validated Workflow Knowledge Base for Bioconductor* (3.0). Zenodo. https://doi.org/10.5281/zenodo.20616356

And, for the execution-grounding methodology:

> Zhang, Y. (2026). *Structure Grounding Is Not Enough: Real Execution as the Ground Truth for LLM-Generated Bioinformatics Workflows* (Version v3). Zenodo. https://doi.org/10.5281/zenodo.20616544

Concept DOIs (always resolve to the latest version): BioMate-KB — https://doi.org/10.5281/zenodo.20616355 · Structure Grounding — https://doi.org/10.5281/zenodo.20616543

## Regenerating the bundle

```bash
# Re-fetch the latest Bioconductor download scores
curl -O https://bioconductor.org/packages/stats/bioc/bioc_pkg_scores.tab

# Regenerate the skill bundle (top 100 by default)
python3 extraction/generate_bundle.py --top 100

# Single package
python3 extraction/extract_skill.py \\
    --db <path-to-biomate-knowledge-db> \\
    --pkg DESeq2 \\
    --out my-deseq2-skill.md
```

The extraction code (`extraction/extract_skill.py`) is intentionally minimal (~300 lines) and reads only from BioMate's public knowledge fields — `tool_knowledge.{use_cases, limitations, alternatives, recommended_parameters, primary_citation, benchmark_papers}` and `tools.scientific_context`. Internal and infrastructure fields are excluded.

## Versioning

This is **v1.0.0** of the bundle. Future versions will track:
- New Bioconductor releases (currently pinned to 3.20)
- Expanded coverage (top-1000 if community demand justifies)
- Refined SKILL.md sections (Q&A, gotchas, additional examples)

## Contributing

Open an issue or PR for:
- Errors in any SKILL.md
- Suggestions for new sections to extract
- Packages missing from the top-100 that should be included

## Acknowledgments

Bioconductor download statistics published by the Bioconductor Core Team. SKILL.md format from [Anthropic Claude Code](https://docs.anthropic.com/en/docs/claude-code/skills-overview).
