#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MsFeatures — subset_feature_grouping
// Perform feature grouping on a manually selected subset of features.
// Input: SummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-msfeatures:1.18.0--r45hdfd78af_0
// R packages: MsFeatures, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: MsFeatures, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize feature groups to NA and assign a placeholder group to the subset of interest
//  * 2. [Core Analysis] Group the subset of features by similar retention times using groupFeatures and SimilarRtimeParam

nextflow.enable.dsl = 2

process BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("MsFeatures", "SummarizedExperiment")
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
    
    # Load required libraries
    library(MsFeatures)
    
    library(SummarizedExperiment)
    # Read the input SummarizedExperiment object from the working directory
    # The pipeline expects a file named "se.rds" containing the SummarizedExperiment
    input_file <- "se.rds"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found in the working directory."))
    }
    
    se <- readRDS(input_file)
    
    # 1. Initialize feature groups to NA and assign a placeholder group to the subset of interest (features 30 to 60)
    featureGroups(se) <- NA_character_
    featureGroups(se)[30:60] <- "FG"
    
    # 2. Group the subset of features by similar retention times using groupFeatures and SimilarRtimeParam
    se <- groupFeatures(se, SimilarRtimeParam(10), rtime = "rtmed")
    
    # Save the resulting SummarizedExperiment object with the updated feature groups
    saveRDS(se, "se_grouped.rds")
    
    # Export the feature grouping results as a CSV table
    fg_df <- data.frame(
      feature_id = rownames(se),
      feature_group = featureGroups(se),
      rtmed = if ("rtmed" %in% colnames(rowData(se))) rowData(se)\$rtmed else NA,
      stringsAsFactors = FALSE
    )
    write.csv(fg_df, "feature_groups.csv", row.names = FALSE)
    
    # Print a summary of the grouping to the console
    cat("Feature grouping completed successfully.\n")
    cat("Number of features grouped:", sum(!is.na(featureGroups(se))), "\n")
    cat("Results saved to 'se_grouped.rds' and 'feature_groups.csv'.\n")

    writeLines(c(
        '"BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING":',
        paste0('    MsFeatures: ', as.character(packageVersion('MsFeatures')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subset_feature_grouping.csv versions.yml
    """
}

workflow BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment ] ]

    main:
    BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING(ch_input)

    emit:
    tables   = BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING.out.tables
    plots    = BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING.out.plots
    objects  = BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING.out.objects
    versions = BIOC_MSFEATURES_SUBSET_FEATURE_GROUPING.out.versions
}
