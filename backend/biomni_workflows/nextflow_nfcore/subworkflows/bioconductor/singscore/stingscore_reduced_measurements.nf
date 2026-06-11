#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: singscore — stingscore_reduced_measurements
// Score panel-based or reduced gene expression data using stably expressed genes for rank calibration.
// Input: small_tgfb_expr_10, tgfb_gs_up, tgfb_gs_dn
// Container: quay.io/biocontainers/bioconductor-singscore:1.30.0--r45hdfd78af_0
// R packages: GSEABase, SummarizedExperiment, singscore
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, SummarizedExperiment, singscore
// Visualizations: density plot, dispersion plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve stable genes using getStableGenes
//  * 2. [Core Analysis] Rank genes with stable genes calibration using rankGenes
//  * 3. [Core Analysis] Score samples using simpleScore

nextflow.enable.dsl = 2

process BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS {
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
    .bm_deps <- c("GSEABase", "SummarizedExperiment", "singscore")
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
    library(singscore)
    library(GSEABase)
    
    # 1. Read user input files from the working directory
    small_tgfb_expr_10 <- readRDS("small_tgfb_expr_10.rds")
    tgfb_gs_up <- readRDS("tgfb_gs_up.rds")
    tgfb_gs_dn <- readRDS("tgfb_gs_dn.rds")
    
    # Define the stable genes used for calibration (Entrez IDs matching the dataset)
    stable_genes <- c('8315', '9391', '23435', '3190')
    
    # 2. Retrieve stable genes (Documented Step 1)
    stable_carcinoma <- getStableGenes(5, type = 'carcinoma')
    
    # 3. Rank genes with stable genes calibration (Documented Step 2)
    rankData_st <- rankGenes(small_tgfb_expr_10, stableGenes = stable_genes)
    
    # 4. Score samples using stingscore (Documented Step 3)
    scoredf_st <- simpleScore(rankData_st, upSet = tgfb_gs_up, downSet = tgfb_gs_dn)
    
    # 5. Write outputs to the working directory
    write.csv(scoredf_st, "scoredf_st.csv", row.names = TRUE)
    saveRDS(rankData_st, "rankData_st.rds")
    saveRDS(scoredf_st, "scoredf_st.rds")
    
    # 6. Generate diagnostic plots
    # Plot rank density for the first sample
    pdf("rank_density_st.pdf", width = 8, height = 6)
    plotRankDensity(rankData_st[, 1, drop = FALSE], upSet = tgfb_gs_up, downSet = tgfb_gs_dn, isInteractive = FALSE)
    dev.off()
    
    # Plot dispersion of scores
    tgfbAnnot <- data.frame(SampleID = colnames(small_tgfb_expr_10), Type = "Unknown")
    tgfbAnnot\$Type[grepl("Ctrl", tgfbAnnot\$SampleID, ignore.case = TRUE)] <- "Control"
    tgfbAnnot\$Type[grepl("TGFb", tgfbAnnot\$SampleID, ignore.case = TRUE)] <- "TGFb"
    
    pdf("dispersion_plot_st.pdf", width = 8, height = 6)
    plotDispersion(scoredf_st, annot = tgfbAnnot\$Type, isInteractive = FALSE)
    dev.off()

    writeLines(c(
        '"BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS":',
        paste0('    singscore: ', as.character(packageVersion('singscore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stingscore_reduced_measurements.csv versions.yml
    """
}

workflow BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ small_tgfb_expr_10, tgfb_gs_up, tgfb_gs_dn ] ]

    main:
    BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS(ch_input)

    emit:
    tables   = BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS.out.tables
    plots    = BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS.out.plots
    objects  = BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS.out.objects
    versions = BIOC_SINGSCORE_STINGSCORE_REDUCED_MEASUREMENTS.out.versions
}
