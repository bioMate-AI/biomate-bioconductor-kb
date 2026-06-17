#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biotmle — biomarker_discovery_tmle
// Identify differentially expressed biomarkers associated with an exposure variable using TMLE and moderated t-statistics, followed by visualization.
// Input: illuminaData
// Container: quay.io/biocontainers/bioconductor-biotmle:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SummarizedExperiment, SuperLearner, biotmle, dplyr
// Visualizations: heatmap, volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Discretize baseline covariates and exposure variables in the SummarizedExperiment object to avoid positivity violations
//  * 2. [Core Analysis] Run biomarkertmle to compute TMLE-based influence curve representations of the Average Treatment Effect (ATE) for each biomarker
//  * 3. [Visualization & Output] Run modtest_ic to apply moderated t-statistics (via limma) on the TMLE outputs
//  * 4. [Visualization & Output] Visualize results using adjusted p-value histograms (plot), supervised heatmaps (heatmap_ic), and volcano plots (volcano_ic)

nextflow.enable.dsl = 2

process BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE {
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
    .bm_deps <- c("dplyr", "biotmle", "BiocParallel", "SuperLearner", "SummarizedExperiment")
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
        library(dplyr)
        library(SummarizedExperiment)
        library(biotmle)
        library(BiocParallel)
        library(SuperLearner)
        
        # Set seed for reproducibility
        set.seed(13847)
        
        # Read the user input file from the working directory
        if (file.exists("illuminaData.rds")) {
          illuminaData <- readRDS("illuminaData.rds")
        } else if (file.exists("illuminaData")) {
          illuminaData <- readRDS("illuminaData")
        } else {
          stop("Input file 'illuminaData' or 'illuminaData.rds' not found in the working directory.")
        }
        
        # 1. Discretize baseline covariates and exposure variables in the SummarizedExperiment object
        col_data_df <- as.data.frame(colData(illuminaData))
        for (col in names(col_data_df)) {
          if (is.numeric(col_data_df[[col]]) && length(unique(col_data_df[[col]])) > 2) {
            col_data_df[[col]] <- as.numeric(col_data_df[[col]] > median(col_data_df[[col]], na.rm = TRUE))
          }
        }
        colData(illuminaData) <- DataFrame(col_data_df)
        
        # Assume the exposure variable is the last column in colData
        varInt_idx <- ncol(colData(illuminaData))
        
        # 2. Run biomarkertmle to compute TMLE-based influence curve representations of the ATE
        biotmle_out <- biomarkertmle(se = illuminaData,
                                     varInt = varInt_idx,
                                     g_lib = c("SL.mean", "SL.glm"),
                                     Q_lib = c("SL.bayesglm", "SL.ranger"),
                                     cv_folds = 2,
                                     bppar_type = SerialParam()
                                    )
        
        # 3. Run modtest_ic to apply moderated t-statistics (via limma) on the TMLE outputs
        modtmle_out <- modtest_ic(biotmle = biotmle_out)
        
        # Save the main output object
        saveRDS(modtmle_out, "modtmle_out.rds")
        
        # Extract and save the topTable results
        top_table_df <- tryCatch({
          modtmle_out@topTable
        }, error = function(e) {
          NULL
        })
        if (!is.null(top_table_df)) {
          write.csv(top_table_df, "top_biomarkers.csv", row.names = TRUE)
        }
        
        # 4. Visualize results using adjusted p-value histograms, supervised heatmaps, and volcano plots
        pdf("pvals_adj_histogram.pdf")
        tryCatch({
          p <- plot(x = modtmle_out, type = "pvals_adj")
          if (inherits(p, "ggplot") || inherits(p, "gg")) print(p)
        }, error = function(e) {
          message("Error plotting pvals_adj: ", e\$message)
        })
        dev.off()
        
        pdf("pvals_raw_histogram.pdf")
        tryCatch({
          p <- plot(x = modtmle_out, type = "pvals_raw")
          if (inherits(p, "ggplot") || inherits(p, "gg")) print(p)
        }, error = function(e) {
          message("Error plotting pvals_raw: ", e\$message)
        })
        dev.off()
        
        varInt_idx <- ncol(colData(illuminaData))
        designVar <- as.data.frame(colData(illuminaData))[, varInt_idx]
        designVar <- as.numeric(designVar == max(designVar))
        
        pdf("heatmap_ic.pdf")
        tryCatch({
          p <- heatmap_ic(x = modtmle_out, left.label = "none", scale = TRUE,
                          clustering.method = "hierarchical", row.dendrogram = TRUE,
                          design = designVar, FDRcutoff = 1, top = 10)
          if (inherits(p, "ggplot") || inherits(p, "gg")) print(p)
        }, error = function(e) {
          message("Error plotting heatmap_ic: ", e\$message)
        })
        dev.off()
        
        pdf("volcano_ic.pdf")
        tryCatch({
          p <- volcano_ic(biotmle = modtmle_out)
          if (inherits(p, "ggplot") || inherits(p, "gg")) print(p)
        }, error = function(e) {
          message("Error plotting volcano_ic: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE":',
        paste0('    biotmle: ', as.character(packageVersion('biotmle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomarker_discovery_tmle.csv versions.yml
    """
}

workflow BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ illuminaData ] ]

    main:
    BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE(ch_input)

    emit:
    tables   = BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE.out.tables
    plots    = BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE.out.plots
    objects  = BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE.out.objects
    versions = BIOC_BIOTMLE_BIOMARKER_DISCOVERY_TMLE.out.versions
}
