#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TDbasedUFE — multiomics_integration
// Integrate multiple omics datasets using kernel tensor decomposition and extract key features across all layers.
// Input: multiomics_list.rds, clinical_covariates.csv
// Container: quay.io/biocontainers/bioconductor-tdbasedufe:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TDbasedUFE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the multi-omics datasets into square similarity matrices (linear kernels) using `convertSquare`. 2. Reformat and bundle th

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION {
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
    .bm_deps <- c("TDbasedUFE")
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
    
    # Read user input files
    CLL_data <- readRDS("multiomics_list.rds")
    CLL_covariates <- read.csv("clinical_covariates.csv", stringsAsFactors = FALSE)
    
    # Execute the documented workflow exactly as specified
    Z <- PrepareSummarizedExperimentTensorSquare(
        sample=matrix(colnames(CLL_data[[1]]),1),
        feature=lapply(CLL_data, rownames),
        value=convertSquare(CLL_data),sampleData=list(CLL_covariates[,1]))
    
    HOSVD <- computeHosvdSqure(Z)
    
    cond <- list(attr(Z,"sampleData")[[1]],attr(Z,"sampleData")[[1]],seq_len(length(CLL_data)))
    
    input_all <- selectSingularValueVectorLarge(HOSVD,cond,input_all=c(1,1))
    
    index <- selectFeatureSquare(HOSVD,input_all,CLL_data,
        de=rep(0.1, length(CLL_data)),interact=FALSE)
    
    # Print the top-ranked features for each omics layer
    for (id in seq_len(length(CLL_data))){
        print(head(tableFeaturesSquare(Z,index,id)))
    }
    
    # Save outputs to files
    saveRDS(Z, "tensor_Z.rds")
    saveRDS(HOSVD, "hosvd_results.rds")
    saveRDS(index, "selected_features_index.rds")
    
    for (id in seq_len(length(CLL_data))) {
        tbl <- tableFeaturesSquare(Z, index, id)
        write.csv(tbl, paste0("selected_features_layer_", id, ".csv"), row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION":',
        paste0('    TDbasedUFE: ', as.character(packageVersion('TDbasedUFE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiomics_integration.csv versions.yml
    """
}

workflow BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multiomics_list.rds, clinical_covariates.csv ] ]

    main:
    BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION.out.tables
    plots    = BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION.out.plots
    objects  = BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION.out.objects
    versions = BIOC_TDBASEDUFE_MULTIOMICS_INTEGRATION.out.versions
}
