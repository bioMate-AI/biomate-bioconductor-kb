#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normalyzerde — normalization_evaluation
// Evaluate multiple normalization methods on raw LC-MS expression data and generate performance plots.
// Input: tiny_data.tsv, tiny_design.tsv
// Container: quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0
// R packages: NormalyzerDE
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("NormalyzerDE")
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
    
    # Load required library
    library(NormalyzerDE)
    
    # Define input file paths (must read EXACTLY these files from the working directory)
    dataFp <- "tiny_data.tsv"
    designFp <- "tiny_design.tsv"
    
    # Verify input files exist
    if (!file.exists(dataFp)) {
        stop(paste("Required input file missing:", dataFp))
    }
    if (!file.exists(designFp)) {
        stop(paste("Required input file missing:", designFp))
    }
    
    # --- Loading data and verifying input ---
    jobName <- "vignette_run"
    experimentObj <- setupRawDataObject(dataFp, designFp, "default", TRUE, "sample", "group")
    normObj <- getVerifiedNormalyzerObject(jobName, experimentObj)
    
    # --- Generate normalizations ---
    normResults <- normMethods(normObj)
    
    # --- Generate performance measures ---
    normResultsWithEval <- analyzeNormalizations(normResults)
    
    # --- Output matrices to file ---
    jobDir <- setupJobDir("vignette_run", tempdir())
    writeNormalizedDatasets(normResultsWithEval, jobDir)
    
    # --- Generate evaluation plots ---
    generatePlots(normResultsWithEval, jobDir)
    
    # Save meaningful results to the current working directory
    # 1. Save the evaluation results object as RDS
    saveRDS(normResultsWithEval, file = "normResultsWithEval.rds")
    
    # 2. Copy the generated normalized matrices and plots to the working directory
    generated_files <- list.files(jobDir, full.names = TRUE, recursive = TRUE)
    if (length(generated_files) > 0) {
        local_out_dir <- "normalyzer_evaluation_results"
        dir.create(local_out_dir, showWarnings = FALSE)
        file.copy(generated_files, local_out_dir, recursive = TRUE)
    }

    writeLines(c(
        '"BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION":',
        paste0('        normalyzerde: ', as.character(packageVersion("normalyzerde")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normalization_evaluation.csv versions.yml
    """
}

workflow BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tiny_data.tsv, tiny_design.tsv ] ]

    main:
    BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION(ch_input)

    emit:
    tables   = BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION.out.tables
    plots    = BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION.out.plots
    objects  = BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION.out.objects
    versions = BIOC_NORMALYZERDE_NORMALIZATION_EVALUATION.out.versions
}
