#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FeatSeekR — unsupervised_feature_selection
// Select and rank a subset of highly reproducible, non-redundant features from high-dimensional replicated data.
// Input: SummarizedExperiment object containing replicated measurements across conditions
// Container: quay.io/biocontainers/bioconductor-featseekr:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FeatSeekR, SummarizedExperiment, pheatmap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform feature selection and ranking using FeatSeek
//  * 2. [Visualization & Output] Visualize the selected features using plotSelectedFeatures

nextflow.enable.dsl = 2

process BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("FeatSeekR", "pheatmap")
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
    library(FeatSeekR)
    library(pheatmap)
    
    # Define input file path
    input_file <- "summarized_experiment.rds"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user-provided SummarizedExperiment object
    sim <- readRDS(input_file)
    
    # 1. Perform feature selection and ranking using FeatSeek
    res <- FeatSeek(sim, max_features=5)
    
    # Save the complete result object
    saveRDS(res, "featseek_results.rds")
    
    # Export the ranked selected features to a CSV file
    selected_features_df <- data.frame(
      Rank = seq_len(nrow(res)),
      Feature = rownames(res)
    )
    
    # Include any additional metadata from rowData if available
    if (ncol(rowData(res)) > 0) {
      selected_features_df <- cbind(selected_features_df, as.data.frame(rowData(res)))
    }
    write.csv(selected_features_df, "selected_features.csv", row.names = FALSE)
    
    # 2. Visualize the selected features using plotSelectedFeatures
    pdf("selected_features_heatmap.pdf", width = 8, height = 6)
    plotSelectedFeatures(res)
    dev.off()

    writeLines(c(
        '"BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION":',
        paste0('    FeatSeekR: ', as.character(packageVersion('FeatSeekR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_feature_selection.csv versions.yml
    """
}

workflow BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment object containing replicated measurements across conditions ] ]

    main:
    BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION(ch_input)

    emit:
    tables   = BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION.out.tables
    plots    = BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION.out.plots
    objects  = BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION.out.objects
    versions = BIOC_FEATSEEKR_UNSUPERVISED_FEATURE_SELECTION.out.versions
}
