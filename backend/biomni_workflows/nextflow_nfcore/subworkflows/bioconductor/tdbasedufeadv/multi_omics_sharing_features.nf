#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TDbasedUFEadv — multi_omics_sharing_features
// Integrate multiple omics datasets sharing the same features but having different samples using projection-based SVD and HOSVD.
// Input: Multi, Clinical, Multi_sample
// Container: quay.io/biocontainers/bioconductor-tdbasedufeadv:1.10.0--r45hdfd78af_0
// R packages: TDbasedUFE, TDbasedUFEadv
// Bioconductor: 3.20 | R: 4.4
// Requires: TDbasedUFE, TDbasedUFEadv
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare a tensor from the list of matrices using
//  * 2. [Input & Preparation] Permute the tensor modes using aperm to align features
//  * 3. [Input & Preparation] Wrap the tensor using PrepareSummarizedExperimentTensor
//  * 4. [Input & Preparation] Compute HOSVD using computeHosvd
//  * 5. [Input & Preparation] Select features using selectFeatureProj in batch mode
//  * 6. [Input & Preparation] Extract and display selected features using tableFeatures

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES {
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
    .bm_deps <- c("TDbasedUFE", "TDbasedUFEadv")
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
    library(TDbasedUFE)
    library(TDbasedUFEadv)
    
    # Check for input files in the working directory
    if (!file.exists("Multi.rds") || !file.exists("Clinical.rds") || !file.exists("Multi_sample.rds")) {
      stop("Required input files (Multi.rds, Clinical.rds, Multi_sample.rds) are missing from the working directory.")
    }
    
    # Read user inputs
    Multi <- readRDS("Multi.rds")
    Clinical <- readRDS("Clinical.rds")
    Multi_sample <- readRDS("Multi_sample.rds")
    
    # Helper to find barcode column in Clinical matching Multi_sample
    find_barcode_col <- function(clin_df, sample_df) {
      ref_barcodes <- as.character(sample_df[, 1])
      ref_clean <- substr(tolower(ref_barcodes), 1, 12)
      overlaps <- sapply(seq_len(ncol(clin_df)), function(j) {
        vals_clean <- substr(tolower(as.character(clin_df[[j]])), 1, 12)
        sum(ref_clean %in% vals_clean)
      })
      best_col <- which.max(overlaps)
      if (overlaps[best_col] == 0) {
        return(20) # Fallback to vignette default
      }
      return(best_col)
    }
    
    # Helper to find clinical condition column in Clinical
    find_condition_col <- function(clin_df) {
      col_names <- colnames(clin_df)
      idx <- grep("pathologic_stage|stage_event|pathologic_categories|clinical_stage|stage", col_names, ignore.case = TRUE)
      if (length(idx) > 0) return(idx[1])
      idx <- grep("status|group|class|gender|sex", col_names, ignore.case = TRUE)
      if (length(idx) > 0) return(idx[1])
      for (j in seq_len(ncol(clin_df))) {
        n_uniq <- length(unique(clin_df[[j]]))
        if (n_uniq > 1 && n_uniq < 10) return(j)
      }
      return(ncol(clin_df))
    }
    
    # Dynamically determine ID columns for matching and condition extraction
    ID_column_of_Multi_sample <- numeric(length(Clinical))
    ID_column_of_Clinical <- numeric(length(Clinical))
    
    for (i in seq_along(Clinical)) {
      ID_column_of_Clinical[i] <- find_barcode_col(Clinical[[i]], Multi_sample[[i]])
      ID_column_of_Multi_sample[i] <- find_condition_col(Clinical[[i]])
    }
    
    # --- Prepare a tensor from the list of matrices using ---
    Z <- prepareTensorfromList(Multi, 10L)
    
    # --- Permute the tensor modes using aperm to align features ---
    Z <- aperm(Z, c(2, 1, 3))
    
    # Determine feature names from the input matrices
    feature_names <- colnames(Multi[[1]])
    if (is.null(feature_names)) {
      feature_names <- paste0("Feature_", seq_len(dim(Z)[1]))
    }
    
    # --- Wrap the tensor using PrepareSummarizedExperimentTensor ---
    Z <- PrepareSummarizedExperimentTensor(
      feature = feature_names,
      sample = array("", 1), value = Z,
      sampleData = prepareCondTCGA(
        Multi_sample, Clinical,
        ID_column_of_Multi_sample, ID_column_of_Clinical
      )
    )
    
    # --- Compute HOSVD using computeHosvd ---
    HOSVD <- computeHosvd(Z)
    
    # --- Select features using selectFeatureProj in batch mode ---
    cond <- attr(Z, "sampleData")
    index <- selectFeatureProj(HOSVD, Multi, cond, de = 1e-3, input_all = 3) # Batch mode
    
    # --- Extract and display selected features using tableFeatures ---
    features_table <- tableFeatures(Z, index)
    print(head(features_table))
    
    # Write outputs to the working directory
    write.csv(features_table, "selected_features.csv", row.names = FALSE)
    saveRDS(HOSVD, "hosvd_results.rds")
    saveRDS(Z, "tensor_Z.rds")
    saveRDS(index, "selected_indices.rds")

    writeLines(c(
        '"BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES":',
        paste0('    TDbasedUFEadv: ', as.character(packageVersion('TDbasedUFEadv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_sharing_features.csv versions.yml
    """
}

workflow BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Multi, Clinical, Multi_sample ] ]

    main:
    BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES(ch_input)

    emit:
    tables   = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES.out.tables
    plots    = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES.out.plots
    objects  = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES.out.objects
    versions = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_FEATURES.out.versions
}
