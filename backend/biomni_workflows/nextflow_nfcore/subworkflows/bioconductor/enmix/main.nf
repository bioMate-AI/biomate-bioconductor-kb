#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: enmix — pipeline_preprocessing
// Perform quality control, preprocessing, and imputation in a single pipeline command.
// Input: directory path for idat files
// Container: quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0
// R packages: ENmix, geneplotter, minfidata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENMIX_PIPELINE_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0"

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
    .bm_deps <- c("ENmix", "geneplotter", "minfidata")
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
    library(ENmix)
    
    # Define the input directory path for raw IDAT files in the working directory
    path <- "idat_files"
    
    # Verify that the input directory exists
    if (!dir.exists(path)) {
      stop(paste("Error: The directory '", path, "' does not exist in the current working directory. Please create it and place your raw IDAT files inside.", sep=""))
    }
    
    message("Step 1: Reading raw IDAT files...")
    # Read raw IDAT files from the specified path
    rgSet <- readidat(path = path, recursive = TRUE)
    
    message("Step 2: Performing initial data pre-processing...")
    # Run initial preprocessing
    beta = mpreprocess(rgSet, nCores = 6)
    
    message("Step 3: Performing quality control, pre-processing, and imputation...")
    # Run the complete pipeline with quality control, filtering, and imputation
    beta = mpreprocess(rgSet, nCores = 6, qc = TRUE, fqcfilter = TRUE, rmcr = TRUE, impute = TRUE)
    
    message("Step 4: Saving preprocessed results...")
    # Save the final beta values matrix as an RDS object
    saveRDS(beta, file = "beta_preprocessed.rds")
    
    # Save a CSV table of the first 1000 rows for quick inspection
    write.csv(head(beta, 1000), file = "beta_preprocessed_subset.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to 'beta_preprocessed.rds' and 'beta_preprocessed_subset.csv'.")

    writeLines(c(
        '"BIOC_ENMIX_PIPELINE_PREPROCESSING":',
        paste0('        enmix: ', as.character(packageVersion("enmix")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pipeline_preprocessing.csv versions.yml
    """
}

workflow BIOC_ENMIX_PIPELINE_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory path for idat files ] ]

    main:
    BIOC_ENMIX_PIPELINE_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_ENMIX_PIPELINE_PREPROCESSING.out.tables
    plots    = BIOC_ENMIX_PIPELINE_PREPROCESSING.out.plots
    objects  = BIOC_ENMIX_PIPELINE_PREPROCESSING.out.objects
    versions = BIOC_ENMIX_PIPELINE_PREPROCESSING.out.versions
}
