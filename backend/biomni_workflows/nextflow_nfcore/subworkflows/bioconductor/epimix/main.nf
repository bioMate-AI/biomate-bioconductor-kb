#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EpiMix — epimix_custom_data_analysis
// Run the core EpiMix analysis on user-provided DNA methylation, gene expression, and sample annotation data across different genomic element modes.
// Input: methylation_matrix.csv, expression_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-epimix:1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EpiMix
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Specify the output directory and run EpiMix in Regular mode to analyze cis-regulatory elements of protein-coding genes
//  * 2. [Core Analysis] Run EpiMix in Enhancer mode using a Roadmap Epigenomics tissue/cell ID to target distal enhancers
//  * 3. [Core Analysis] Run EpiMix in miRNA mode using matched miRNA expression data
//  * 4. [Core Analysis] Run EpiMix in lncRNA mode using matched lncRNA expression data

nextflow.enable.dsl = 2

process BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("EpiMix")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required library
    library(EpiMix)
    
    # Define output directory
    outputDirectory <- "./epimix_output"
    if (!dir.exists(outputDirectory)) {
      dir.create(outputDirectory, recursive = TRUE)
    }
    
    # Stage 1: Read user-provided DNA methylation data
    if (!file.exists("methylation_matrix.csv")) {
      stop("Error: User input file 'methylation_matrix.csv' not found.")
    }
    METProcessedData <- as.matrix(read.csv("methylation_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Save preprocessed methylation data
    saveRDS(METProcessedData, file = file.path(outputDirectory, "METProcessedData.rds"))
    if (nrow(METProcessedData) > 0) {
      write.csv(as.data.frame(METProcessedData[1:min(100, nrow(METProcessedData)), 1:min(5, ncol(METProcessedData))]), 
                file = file.path(outputDirectory, "METProcessedData_preview.csv"))
    }
    
    # Stage 2: Read user-provided gene expression data
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: User input file 'expression_matrix.csv' not found.")
    }
    GEProcessedData <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Save preprocessed gene expression data
    saveRDS(GEProcessedData, file = file.path(outputDirectory, "GEProcessedData.rds"))
    if (nrow(GEProcessedData) > 0) {
      write.csv(as.data.frame(GEProcessedData[1:min(100, nrow(GEProcessedData)), 1:min(5, ncol(GEProcessedData))]), 
                file = file.path(outputDirectory, "GEProcessedData_preview.csv"))
    }
    
    # Stage 3: Read user-provided sample annotation
    if (!file.exists("sample_metadata.csv")) {
      stop("Error: User input file 'sample_metadata.csv' not found.")
    }
    sample.info <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
    
    # Save sample annotation
    write.csv(sample.info, file = file.path(outputDirectory, "sample_info.csv"), row.names = FALSE)
    
    # Extract groups for comparison
    groups <- unique(sample.info\$sample.type)
    if (length(groups) < 2) {
      stop("Error: 'sample.type' column in sample_metadata.csv must contain at least two groups.")
    }
    group.1 <- groups[1]
    group.2 <- groups[2]
    
    # Stage 4: Run the complete analysis for Regular, Enhancer, miRNA, and lncRNA modes
    roadmap.epigenome.ids = "E097"
    
    # Regular mode
    EpiMixResults_Regular <- EpiMix(methylation.data = METProcessedData, 
                                    gene.expression.data = GEProcessedData, 
                                    sample.info = sample.info, 
                                    group.1 = group.1, 
                                    group.2 = group.2, 
                                    met.platform = "HM450", 
                                    OutputRoot = outputDirectory)
    
    saveRDS(EpiMixResults_Regular, file = file.path(outputDirectory, "EpiMixResults_Regular.rds"))
    if (!is.null(EpiMixResults_Regular\$FunctionalPairs)) {
      write.csv(EpiMixResults_Regular\$FunctionalPairs, file = file.path(outputDirectory, "FunctionalPairs_Regular.csv"), row.names = FALSE)
    }
    
    # Enhancer mode
    EpiMixResults_Enhancer <- EpiMix(methylation.data = METProcessedData, 
                                     gene.expression.data = GEProcessedData, 
                                     mode = "Enhancer", 
                                     roadmap.epigenome.ids = roadmap.epigenome.ids, 
                                     sample.info = sample.info, 
                                     group.1 = group.1, 
                                     group.2 = group.2, 
                                     met.platform = "HM450", 
                                     OutputRoot = outputDirectory)
    
    saveRDS(EpiMixResults_Enhancer, file = file.path(outputDirectory, "EpiMixResults_Enhancer.rds"))
    if (!is.null(EpiMixResults_Enhancer\$FunctionalPairs)) {
      write.csv(EpiMixResults_Enhancer\$FunctionalPairs, file = file.path(outputDirectory, "FunctionalPairs_Enhancer.csv"), row.names = FALSE)
    }
    
    # miRNA mode
    EpiMixResults_miRNA <- EpiMix(methylation.data = METProcessedData, 
                                  gene.expression.data = GEProcessedData, 
                                  mode = "miRNA", 
                                  sample.info = sample.info, 
                                  group.1 = group.1, 
                                  group.2 = group.2, 
                                  met.platform = "HM450", 
                                  OutputRoot = outputDirectory)
    
    saveRDS(EpiMixResults_miRNA, file = file.path(outputDirectory, "EpiMixResults_miRNA.rds"))
    if (!is.null(EpiMixResults_miRNA\$FunctionalPairs)) {
      write.csv(EpiMixResults_miRNA\$FunctionalPairs, file = file.path(outputDirectory, "FunctionalPairs_miRNA.csv"), row.names = FALSE)
    }
    
    # lncRNA mode
    EpiMixResults_lncRNA <- EpiMix(methylation.data = METProcessedData, 
                                   gene.expression.data = GEProcessedData, 
                                   mode = "lncRNA", 
                                   sample.info = sample.info, 
                                   group.1 = group.1, 
                                   group.2 = group.2, 
                                   met.platform = "HM450", 
                                   OutputRoot = outputDirectory)
    
    saveRDS(EpiMixResults_lncRNA, file = file.path(outputDirectory, "EpiMixResults_lncRNA.rds"))
    if (!is.null(EpiMixResults_lncRNA\$FunctionalPairs)) {
      write.csv(EpiMixResults_lncRNA\$FunctionalPairs, file = file.path(outputDirectory, "FunctionalPairs_lncRNA.csv"), row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS":',
        paste0('    EpiMix: ', as.character(packageVersion('EpiMix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epimix_custom_data_analysis.csv versions.yml
    """
}

workflow BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methylation_matrix.csv, expression_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS.out.tables
    plots    = BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS.out.plots
    objects  = BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS.out.objects
    versions = BIOC_EPIMIX_EPIMIX_CUSTOM_DATA_ANALYSIS.out.versions
}
