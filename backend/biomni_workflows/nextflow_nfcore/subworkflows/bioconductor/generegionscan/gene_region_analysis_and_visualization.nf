#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneRegionScan — gene_region_analysis_and_visualization
// Analyze and visualize probe-level expression, exon structure, coexpression, and association with sample metadata.
// Input: exampleProbeLevelSet, mrna, genomic
// Container: quay.io/biocontainers/bioconductor-generegionscan:1.66.0--r45hdfd78af_0
// R packages: Biobase, Biostrings, GeneRegionScan
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Biostrings, GeneRegionScan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot summarized probe expression along the gene using plotOnGene
//  * 2. [Visualization & Output] Zoom in on a specific region and overlay exon structure using plotOnGene and exonStructure
//  * 3. [Visualization & Output] Test and visualize probe expression differences between sample groups (e.g., gender or genotype) using plotOnGene with testType
//  * 4. [Visualization & Output] Analyze and plot pairwise probe coexpression using plotCoexpression
//  * 5. [Core Analysis] Perform a comprehensive gene region scan using geneRegionScan

nextflow.enable.dsl = 2

process BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "Biostrings", "GeneRegionScan")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GeneRegionScan)
    library(Biostrings)
    library(Biobase)
    
    # Helper function to read the user-provided input files from the working directory
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found in working directory:", filename))
      }
    }
    
    # Read user input files
    exampleProbeLevelSet <- read_input("exampleProbeLevelSet")
    mrna <- read_input("mrna")
    genomic <- read_input("genomic")
    
    # Export a preview of the sample metadata
    metadata_preview <- pData(exampleProbeLevelSet)[1:3, ]
    write.csv(metadata_preview, "sample_metadata_preview.csv", row.names = TRUE)
    
    # 1. Plot summarized probe expression along the gene
    pdf("plot1_gene_expression.pdf", width = 10, height = 7)
    plotOnGene(exampleProbeLevelSet, mrna)
    dev.off()
    
    # 2. Zoom in on a specific region and overlay exon structure
    pdf("plot2_zoom_exon_structure.pdf", width = 10, height = 7)
    plotOnGene(exampleProbeLevelSet, mrna, summaryType="dots", interval=c(500,1000))
    exonStructure(mrna, genomic)
    dev.off()
    
    # 3. Test and visualize probe expression differences between sample groups (gender)
    pdf("plot3_gender_wilcoxon.pdf", width = 10, height = 7)
    plotOnGene(exampleProbeLevelSet, mrna, label="gender", testType="wilcoxon", verbose=FALSE)
    exonStructure(mrna, genomic)
    dev.off()
    
    # 4. Test and visualize probe expression differences between sample groups (genotype1)
    pdf("plot4_genotype1_lm.pdf", width = 10, height = 7)
    plotOnGene(exampleProbeLevelSet, mrna, label="genotype1", testType="linear model", verbose=FALSE)
    exonStructure(mrna, genomic)
    dev.off()
    
    # 5. Analyze and plot pairwise probe coexpression
    mrna_subset <- mrna[[1]]
    mrna_subset <- mrna_subset[500:1000]
    
    pdf("plot5_coexpression.pdf", width = 10, height = 10)
    plotCoexpression(exampleProbeLevelSet, gene=mrna_subset, correlationCutoff=0.5, probeLevelInfo=c("probeid","sequence"), verbose=FALSE)
    dev.off()
    
    # 6. Perform a comprehensive gene region scan
    pdf("plot6_gene_region_scan.pdf", width = 10, height = 10)
    geneRegionScan(exampleProbeLevelSet, gene=mrna, genomicData=genomic, label="genotype3", testType="linear model", correlationCutoff=0.5, probeLevelInfo=c("probeid","sequence"), verbose=FALSE)
    dev.off()

    writeLines(c(
        '"BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION":',
        paste0('    GeneRegionScan: ', as.character(packageVersion('GeneRegionScan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_region_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleProbeLevelSet, mrna, genomic ] ]

    main:
    BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_GENEREGIONSCAN_GENE_REGION_ANALYSIS_AND_VISUALIZATION.out.versions
}
