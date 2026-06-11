#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TDbasedUFEadv — multi_omics_sharing_samples
// Integrate multiple omics datasets sharing the same samples using projection-based SVD and HOSVD.
// Input: CLL_data, CLL_covariates
// Container: quay.io/biocontainers/bioconductor-tdbasedufeadv:1.10.0--r45hdfd78af_0
// R packages: TDbasedUFE, TDbasedUFEadv
// Bioconductor: 3.20 | R: 4.4
// Requires: TDbasedUFE, TDbasedUFEadv
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare a tensor from the list of matrices using prepareTensorfromList. 2. Wrap the tensor in a SummarizedExperiment-like object u

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES {
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
    .bm_deps <- c("TDbasedUFE", "TDbasedUFEadv")
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
    library(TDbasedUFE)
    library(TDbasedUFEadv)
    
    # Read user inputs from the working directory
    CLL_data <- readRDS("CLL_data.rds")
    CLL_covariates <- readRDS("CLL_covariates.rds")
    
    # 1. Prepare a tensor from the list of matrices
    Z <- prepareTensorfromList(CLL_data, 10L)
    
    # 2. Wrap the tensor in a SummarizedExperiment-like object
    Z <- PrepareSummarizedExperimentTensor(
      feature = character("1"),
      sample = array(colnames(CLL_data[[1]]), 1),
      value = Z,
      sampleData = list(CLL_covariates[, 1])
    )
    
    # 3. Compute HOSVD
    HOSVD <- computeHosvd(Z, scale = FALSE)
    
    # 4. Select singular value vectors
    cond <- list(NULL, attr(Z, "sampleData")[[1]], seq_along(CLL_data))
    input_all <- selectSingularValueVectorLarge(HOSVD, cond, input_all = c(1, 1))
    
    # 5. Select features across individual omics profiles
    HOSVD\$U[[1]] <- HOSVD\$U[[2]]
    index_all <- selectFeatureSquare(HOSVD, input_all, CLL_data, de = rep(0.1, length(CLL_data)), interact = FALSE)
    
    # 6. Extract, print, and save selected features
    for (id in seq_along(CLL_data)) {
      attr(Z, "feature") <- rownames(CLL_data[[id]])
      features_table <- tableFeatures(Z, index_all[[id]])
      
      # Print to console
      cat(paste("\n--- Selected Features for Omics Profile", id, "---\n"))
      print(features_table)
      
      # Save to CSV
      write.csv(
        features_table, 
        file = paste0("selected_features_omics_", id, ".csv"), 
        row.names = FALSE
      )
    }
    
    # Save key RDS objects for downstream analysis
    saveRDS(HOSVD, "HOSVD_results.rds")
    saveRDS(index_all, "selected_features_indices.rds")
    saveRDS(Z, "SummarizedExperimentTensor.rds")

    writeLines(c(
        '"BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES":',
        paste0('    TDbasedUFEadv: ', as.character(packageVersion('TDbasedUFEadv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_sharing_samples.csv versions.yml
    """
}

workflow BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CLL_data, CLL_covariates ] ]

    main:
    BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES(ch_input)

    emit:
    tables   = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES.out.tables
    plots    = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES.out.plots
    objects  = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES.out.objects
    versions = BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES.out.versions
}
