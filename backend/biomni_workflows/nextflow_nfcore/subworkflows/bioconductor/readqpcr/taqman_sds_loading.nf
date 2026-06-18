#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ReadqPCR — taqman_sds_loading
// Read Sequence Detection Systems (SDS) software output files (Taqman Low Density Arrays) into a single qPCRBatch object.
// Input: example.txt, example2.txt
// Container: quay.io/biocontainers/bioconductor-readqpcr:1.56.0--r45hdfd78af_0
// R packages: ReadqPCR
// Bioconductor: 3.20 | R: 4.4
// Requires: ReadqPCR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read a single SDS file using read.taqman to create a
//  * 2. [Input & Preparation] Read multiple SDS files using read.taqman (if the

nextflow.enable.dsl = 2

process BIOC_READQPCR_TAQMAN_SDS_LOADING {
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
    .bm_deps <- c("ReadqPCR")
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
    
    # Load the required Bioconductor library
    library(ReadqPCR)
    
    # Define input file paths in the working directory as specified by the user
    taqman.example <- "example.txt"
    taqman.example.second.file <- "example2.txt"
    
    # Verify that the primary required input file exists
    if (!file.exists(taqman.example)) {
      stop(paste("Error: Required input file missing in the working directory:", taqman.example))
    }
    
    # --- Read a single SDS file using read.taqman to create a ---
    message("Reading single SDS file...")
    qPCRBatch.taq <- read.taqman(taqman.example)
    
    # Save outputs for the single-file workflow
    message("Saving outputs for single-file workflow...")
    saveRDS(qPCRBatch.taq, "qPCRBatch_single.rds")
    write.csv(exprs(qPCRBatch.taq), "exprs_single.csv", row.names = TRUE)
    write.csv(pData(qPCRBatch.taq), "pData_single.csv", row.names = TRUE)
    
    # Extract and save well order information if available
    well_order_single <- exprs.well.order(qPCRBatch.taq)
    if (!is.null(well_order_single)) {
      write.csv(well_order_single, "well_order_single.csv", row.names = TRUE)
    }
    
    # --- Read multiple SDS files using read.taqman (if the ---
    if (file.exists(taqman.example.second.file)) {
      message("Reading multiple SDS files...")
      qPCRBatch.taq.two.files <- read.taqman(taqman.example, 
                                             taqman.example.second.file)
      
      # Save outputs for the two-file workflow
      message("Saving outputs for multiple-file workflow...")
      saveRDS(qPCRBatch.taq.two.files, "qPCRBatch_two_files.rds")
      write.csv(exprs(qPCRBatch.taq.two.files), "exprs_two_files.csv", row.names = TRUE)
      write.csv(pData(qPCRBatch.taq.two.files), "pData_two_files.csv", row.names = TRUE)
      
      well_order_two <- exprs.well.order(qPCRBatch.taq.two.files)
      if (!is.null(well_order_two)) {
        write.csv(well_order_two, "well_order_two_files.csv", row.names = TRUE)
      }
    } else {
      message("Optional second file 'example2.txt' not found. Skipping two-file workflow.")
    }
    
    message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_READQPCR_TAQMAN_SDS_LOADING":',
        paste0('    ReadqPCR: ', as.character(packageVersion('ReadqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taqman_sds_loading.csv versions.yml
    """
}

workflow BIOC_READQPCR_TAQMAN_SDS_LOADING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.txt, example2.txt ] ]

    main:
    BIOC_READQPCR_TAQMAN_SDS_LOADING(ch_input)

    emit:
    tables   = BIOC_READQPCR_TAQMAN_SDS_LOADING.out.tables
    plots    = BIOC_READQPCR_TAQMAN_SDS_LOADING.out.plots
    objects  = BIOC_READQPCR_TAQMAN_SDS_LOADING.out.objects
    versions = BIOC_READQPCR_TAQMAN_SDS_LOADING.out.versions
}
