#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AWFisher — biomarker_categorization_and_pattern_detection
// Detect differential expression patterns (meta-patterns) and calculate variability indices across studies.
// Input: studies
// Container: quay.io/biocontainers/bioconductor-awfisher:1.24.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AWFisher, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the list of studies with data and labels
//  * 2. [Core Analysis] Run biomarkerCategorization with a user-defined differential expression function (e.g., function_limma) and permutation count B
//  * 3. [Core Analysis] Extract the variability index and dissimilarity matrix

nextflow.enable.dsl = 2

process BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(AWFisher)
    library(limma)
    
    # Define the user-defined differential expression function required by biomarkerCategorization
    function_limma <- function(data, label) {
      design <- model.matrix(~label)
      fit <- limma::lmFit(data, design)
      fit <- limma::eBayes(fit)
      return(fit\$p.value[, 2])
    }
    
    # 1. Prepare the list of studies with data and labels
    # Read the user input file 'studies.rds' from the working directory
    if (!file.exists("studies.rds")) {
      stop("Error: 'studies.rds' file not found in the working directory.")
    }
    
    studies <- readRDS("studies.rds")
    
    # Validate the input structure
    if (!is.list(studies)) {
      stop("Error: Input 'studies' must be a list.")
    }
    for (i in seq_along(studies)) {
      if (!all(c("data", "label") %in% names(studies[[i]]))) {
        stop(paste("Error: Study", i, "must contain both 'data' and 'label' elements."))
      }
    }
    
    # Set seed for reproducibility of permutations
    set.seed(15213)
    
    # 2. Run biomarkerCategorization with the user-defined function and permutation count B
    result <- biomarkerCategorization(studies, function_limma, B = 100, DEindex = NULL)
    
    # 3. Extract and display the variability index and dissimilarity matrix
    de_count <- sum(result\$DEindex)
    cat("Number of differentially expressed genes (FDR < 0.05):", de_count, "\n")
    
    cat("Head of variability index:\n")
    print(head(result\$varibility, n = 2))
    
    cat("Subset of dissimilarity matrix:\n")
    print(result\$dissimilarity[1:4, 1:4])
    
    # 4. Write named output files for the meaningful results
    # Save the complete result object
    saveRDS(result, "biomarker_categorization_result.rds")
    
    # Save the DE index
    de_df <- data.frame(
      Gene = rownames(studies[[1]]\$data),
      DEindex = result\$DEindex
    )
    write.csv(de_df, "de_index.csv", row.names = FALSE)
    
    # Save the variability index
    var_df <- as.data.frame(result\$varibility)
    rownames(var_df) <- rownames(studies[[1]]\$data)
    colnames(var_df) <- paste0("Study_", seq_len(ncol(var_df)))
    write.csv(var_df, "variability_index.csv", row.names = TRUE)
    
    # Save the dissimilarity matrix
    write.csv(as.data.frame(result\$dissimilarity), "dissimilarity_matrix.csv", row.names = TRUE)
    
    cat("Pipeline completed successfully. Outputs saved to 'biomarker_categorization_result.rds', 'de_index.csv', 'variability_index.csv', and 'dissimilarity_matrix.csv'.\n")

    writeLines(c(
        '"BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION":',
        paste0('    AWFisher: ', as.character(packageVersion('AWFisher')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomarker_categorization_and_pattern_detection.csv versions.yml
    """
}

workflow BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ studies ] ]

    main:
    BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION(ch_input)

    emit:
    tables   = BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION.out.tables
    plots    = BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION.out.plots
    objects  = BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION.out.objects
    versions = BIOC_AWFISHER_BIOMARKER_CATEGORIZATION_AND_PATTERN_DETECTION.out.versions
}
