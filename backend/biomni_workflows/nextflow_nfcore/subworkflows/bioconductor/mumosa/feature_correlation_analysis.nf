#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mumosa — feature_correlation_analysis
// Identify and analyze correlations between features of different modalities (e.g., RNA genes and ADT proteins), optionally accounting for batch effects.
// Input: sce2
// Container: quay.io/biocontainers/bioconductor-mumosa:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, mumosa
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute exact pairwise correlations between features of different modalities using computeCorrelations()
//  * 2. [Core Analysis] Compute exact pairwise correlations with blocking factors using computeCorrelations(..., block=b)
//  * 3. [Core Analysis] Perform approximate search for top correlated features using findTopCorrelations()

nextflow.enable.dsl = 2

process BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(mumosa)
    
    # 1. Read the input SingleCellExperiment object
    sce2_path <- "sce2"
    if (!file.exists(sce2_path) && file.exists("sce2.rds")) {
      sce2_path <- "sce2.rds"
    }
    
    if (!file.exists(sce2_path)) {
      stop("Error: Input file 'sce2' or 'sce2.rds' not found in the working directory.")
    }
    
    sce2 <- readRDS(sce2_path)
    
    # Ensure alternative experiment exists and has enough features
    if (length(altExpNames(sce2)) == 0) {
      stop("Error: The input SingleCellExperiment object does not contain any alternative experiments.")
    }
    
    # 2. Compute exact pairwise correlations between features of different modalities
    cor.all <- computeCorrelations(sce2, altExp(sce2))
    cor.all.ordered <- cor.all[order(cor.all\$p.value),]
    
    # Save exact correlation results
    write.csv(as.data.frame(cor.all.ordered), file = "cor_all_ordered.csv", row.names = FALSE)
    
    # 3. Compute exact pairwise correlations with blocking factors
    b <- sce2\$batch
    cor.all.batch <- computeCorrelations(sce2, altExp(sce2), block=b)
    
    # Save batch-corrected correlation results
    write.csv(as.data.frame(cor.all.batch), file = "cor_all_batch.csv", row.names = FALSE)
    
    # 4. Perform approximate search for top correlated features
    set.seed(100001) # for IRLBA.
    top.cor <- findTopCorrelations(sce2, y=altExp(sce2), number=10)
    
    # Save top correlation results
    write.csv(as.data.frame(top.cor\$positive), file = "top_cor_positive.csv", row.names = FALSE)
    write.csv(as.data.frame(top.cor\$negative), file = "top_cor_negative.csv", row.names = FALSE)
    saveRDS(top.cor, file = "top_cor.rds")
    
    # Print summary to console
    cat("Feature correlation analysis completed successfully.\n")
    cat(sprintf("Exact correlations computed for %d pairs.\n", nrow(cor.all)))
    cat(sprintf("Top positive correlations found: %d pairs.\n", nrow(top.cor\$positive)))
    cat(sprintf("Top negative correlations found: %d pairs.\n", nrow(top.cor\$negative)))

    writeLines(c(
        '"BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS":',
        paste0('    mumosa: ', as.character(packageVersion('mumosa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce2 ] ]

    main:
    BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_MUMOSA_FEATURE_CORRELATION_ANALYSIS.out.versions
}
