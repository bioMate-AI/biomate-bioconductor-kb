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
//  * 1. [Visualization & Output] Prepare a tensor from the list of matrices
//  * 2. [Visualization & Output] Wrap the tensor in a SummarizedExperiment-like object
//  * 3. [Visualization & Output] Compute HOSVD
//  * 4. [Visualization & Output] Select singular value vectors
//  * 5. [Visualization & Output] Select features across individual omics profiles
//  * 6. [Visualization & Output] Extract, print, and save selected features

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFEADV_MULTI_OMICS_SHARING_SAMPLES {
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
    
    # Read user inputs from the working directory
    CLL_data <- readRDS("CLL_data.rds")
    CLL_covariates <- readRDS("CLL_covariates.rds")
    
    # --- Prepare a tensor from the list of matrices ---
    Z <- prepareTensorfromList(CLL_data, 10L)
    
    # --- Wrap the tensor in a SummarizedExperiment-like object ---
    Z <- PrepareSummarizedExperimentTensor(
      feature = character("1"),
      sample = array(colnames(CLL_data[[1]]), 1),
      value = Z,
      sampleData = list(CLL_covariates[, 1])
    )
    
    # --- Compute HOSVD ---
    HOSVD <- computeHosvd(Z, scale = FALSE)
    
    # --- Select singular value vectors ---
    cond <- list(NULL, attr(Z, "sampleData")[[1]], seq_along(CLL_data))
    input_all <- selectSingularValueVectorLarge(HOSVD, cond, input_all = c(1, 1))
    
    # --- Select features across individual omics profiles ---
    HOSVD\$U[[1]] <- HOSVD\$U[[2]]
    index_all <- selectFeatureSquare(HOSVD, input_all, CLL_data, de = rep(0.1, length(CLL_data)), interact = FALSE)
    
    # --- Extract, print, and save selected features ---
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
