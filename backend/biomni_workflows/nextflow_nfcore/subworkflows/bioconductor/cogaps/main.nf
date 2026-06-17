#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CoGAPS — standard_cogaps_workflow
// Run standard sequential Bayesian NMF on a gene expression matrix to learn latent patterns.
// Input: modsimdata
// Container: quay.io/biocontainers/bioconductor-cogaps:3.30.0--r45ha27e39d_0
// R packages: CoGAPS, Seurat, viridis
// Bioconductor: 3.20 | R: 4.4
// Requires: CoGAPS
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize parameters using new("CogapsParams")
//  * 2. [Core Analysis] Modify parameters using setParam()
//  * 3. [Core Analysis] Run factorization using CoGAPS()
//  * 4. [Core Analysis] Extract sample factors and feature loadings from the CogapsResult object

nextflow.enable.dsl = 2

process BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW {
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
    .bm_deps <- c("CoGAPS", "Seurat", "viridis")
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
    library(CoGAPS)
    
    # ----------------------------------------------------------------------
    # 1. Load User Input
    # ----------------------------------------------------------------------
    # The pipeline expects 'modsimdata' in the working directory.
    # We check for common extensions (.rds, .csv, .tsv, .txt) or the bare name.
    if (file.exists("modsimdata.rds")) {
      modsimdata <- readRDS("modsimdata.rds")
    } else if (file.exists("modsimdata.csv")) {
      modsimdata <- read.csv("modsimdata.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("modsimdata.tsv")) {
      modsimdata <- read.delim("modsimdata.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("modsimdata.txt")) {
      modsimdata <- read.table("modsimdata.txt", header = TRUE, row.names = 1, check.names = FALSE)
    } else if (file.exists("modsimdata")) {
      modsimdata <- tryCatch({
        read.csv("modsimdata", row.names = 1, check.names = FALSE)
      }, error = function(e) {
        read.table("modsimdata", header = TRUE, row.names = 1, check.names = FALSE)
      })
    } else {
      stop("Required input file 'modsimdata' (with or without extension .csv/.tsv/.rds) not found in the working directory.")
    }
    
    # Ensure the input is formatted as a matrix
    modsimdata <- as.matrix(modsimdata)
    
    # ----------------------------------------------------------------------
    # 2. Initialize and Modify Parameters
    # ----------------------------------------------------------------------
    params <- new("CogapsParams", nPatterns=6)
    params
    getParam(params, "nPatterns")
    
    params <- setParam(params, "nPatterns", 3)
    getParam(params, "nPatterns")
    
    # ----------------------------------------------------------------------
    # 3. Run CoGAPS Factorization
    # ----------------------------------------------------------------------
    cogapsresult <- CoGAPS(modsimdata, params, outputFrequency = 10000)
    cogapsresult
    
    # ----------------------------------------------------------------------
    # 4. Extract and Save Results
    # ----------------------------------------------------------------------
    sample_factors <- cogapsresult@sampleFactors
    feature_loadings <- cogapsresult@featureLoadings
    
    # Save the full result object
    saveRDS(cogapsresult, "cogaps_result.rds")
    
    # Save extracted matrices to CSV
    write.csv(sample_factors, "sample_factors.csv", row.names = TRUE)
    write.csv(feature_loadings, "feature_loadings.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW":',
        paste0('    CoGAPS: ', as.character(packageVersion('CoGAPS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_cogaps_workflow.csv versions.yml
    """
}

workflow BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ modsimdata ] ]

    main:
    BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW.out.tables
    plots    = BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW.out.plots
    objects  = BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW.out.objects
    versions = BIOC_COGAPS_STANDARD_COGAPS_WORKFLOW.out.versions
}
