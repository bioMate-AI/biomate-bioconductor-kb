#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SeqGate — seqgate_filtering
// Filter lowly expressed features from a transcriptomics count dataset using replicate-based thresholding.
// Input: counts_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-seqgate:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SeqGate, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the SeqGate package and prepare the SummarizedExperiment object from the count matrix and condition metadata
//  * 2. [Core Analysis] Apply the SeqGate filtering method using applySeqGate with default parameters
//  * 3. [Core Analysis] Extract the kept features and the applied threshold
//  * 4. [Core Analysis] Optionally apply SeqGate with custom parameters (prop0, percentile, propUpThresh) to refine filtering

nextflow.enable.dsl = 2

process BIOC_SEQGATE_SEQGATE_FILTERING {
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
    .bm_deps <- c("SeqGate", "SummarizedExperiment")
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
      library(SummarizedExperiment)
  library(SeqGate)
    
    # 1. Read User Input Files
    if (!file.exists("counts_matrix.csv")) {
      stop("Error: 'counts_matrix.csv' not found in the working directory.")
    }
    if (!file.exists("sample_metadata.csv")) {
      stop("Error: 'sample_metadata.csv' not found in the working directory.")
    }
    
    counts_data <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    metadata_data <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts and metadata columns/rows
    common_samples <- intersect(colnames(counts_data), rownames(metadata_data))
    if (length(common_samples) == 0) {
      # Try matching if sample names are in a column instead of row names
      for (col in colnames(metadata_data)) {
        if (any(colnames(counts_data) %in% metadata_data[[col]])) {
          rownames(metadata_data) <- metadata_data[[col]]
          break
        }
      }
      common_samples <- intersect(colnames(counts_data), rownames(metadata_data))
    }
    
    if (length(common_samples) == 0) {
      stop("Error: No matching sample identifiers found between counts_matrix.csv and sample_metadata.csv.")
    }
    
    counts_data <- counts_data[, common_samples, drop = FALSE]
    metadata_data <- metadata_data[common_samples, , drop = FALSE]
    
    # Identify the biological conditions column
    cond_col <- "Conditions"
    if (!cond_col %in% colnames(metadata_data)) {
      potential_cols <- grep("cond|group|treatment|class", colnames(metadata_data), ignore.case = TRUE, value = TRUE)
      if (length(potential_cols) > 0) {
        cond_col <- potential_cols[1]
      } else {
        cond_col <- colnames(metadata_data)[1]
      }
    }
    
    cond <- metadata_data[[cond_col]]
    
    # 2. Prepare the SummarizedExperiment Object
    rowData <- DataFrame(row.names = rownames(counts_data))
    colData <- DataFrame(Conditions = cond, row.names = colnames(counts_data))
    counts_strub <- SummarizedExperiment(
                      assays = list(counts = as.matrix(counts_data)),
                      rowData = rowData,
                      colData = colData)
    
    # 3. Apply SeqGate Filtering with Default Parameters
    counts_strub_default <- applySeqGate(counts_strub, "counts", "Conditions")
    
    # Extract results for default run
    keptGenes_default <- assay(counts_strub_default[rowData(counts_strub_default)\$onFilter == TRUE,])
    thresh_default <- metadata(counts_strub_default)\$threshold
    filteredOut_default <- assay(counts_strub_default[rowData(counts_strub_default)\$onFilter == FALSE,])
    
    # Write default outputs
    write.csv(as.data.frame(keptGenes_default), "kept_genes_default.csv", row.names = TRUE)
    write.csv(as.data.frame(filteredOut_default), "filtered_genes_default.csv", row.names = TRUE)
    writeLines(as.character(thresh_default), "threshold_default.txt")
    
    # 4. Apply SeqGate Filtering with Custom Parameters
    counts_strub_custom <- applySeqGate(counts_strub, "counts", "Conditions",
                                        prop0 = 1/3,
                                        percentile = 0.8,
                                        propUpThresh = 0.5)
    
    # Extract results for custom run
    keptGenes_custom <- assay(counts_strub_custom[rowData(counts_strub_custom)\$onFilter == TRUE,])
    thresh_custom <- metadata(counts_strub_custom)\$threshold
    filteredOut_custom <- assay(counts_strub_custom[rowData(counts_strub_custom)\$onFilter == FALSE,])
    
    # Write custom outputs
    write.csv(as.data.frame(keptGenes_custom), "kept_genes_custom.csv", row.names = TRUE)
    write.csv(as.data.frame(filteredOut_custom), "filtered_genes_custom.csv", row.names = TRUE)
    writeLines(as.character(thresh_custom), "threshold_custom.txt")
    
    # Save the final SummarizedExperiment object
    saveRDS(counts_strub_custom, "counts_strub_final.rds")
    
    cat("SeqGate filtering completed successfully.\n")

    writeLines(c(
        '"BIOC_SEQGATE_SEQGATE_FILTERING":',
        paste0('    SeqGate: ', as.character(packageVersion('SeqGate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqgate_filtering.csv versions.yml
    """
}

workflow BIOC_SEQGATE_SEQGATE_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_SEQGATE_SEQGATE_FILTERING(ch_input)

    emit:
    tables   = BIOC_SEQGATE_SEQGATE_FILTERING.out.tables
    plots    = BIOC_SEQGATE_SEQGATE_FILTERING.out.plots
    objects  = BIOC_SEQGATE_SEQGATE_FILTERING.out.objects
    versions = BIOC_SEQGATE_SEQGATE_FILTERING.out.versions
}
