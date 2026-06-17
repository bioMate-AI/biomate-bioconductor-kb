#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sccb2 — detailed_cb2_pipeline
// Run the step-by-step CB2 pipeline to read raw 10x data, evaluate the background cutoff, identify real cells, and filter out damaged cells.
// Input: raw_data_directory
// Container: quay.io/biocontainers/bioconductor-sccb2:1.20.0--r45hdfd78af_0
// R packages: Matrix, SummarizedExperiment, scCB2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCCB2_DETAILED_CB2_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sccb2:1.20.0--r45hdfd78af_0"

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
    .bm_deps <- c("Matrix", "SummarizedExperiment", "scCB2")
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
    library(scCB2)
    library(SummarizedExperiment)
    library(Matrix)
    
    # Define input directory as specified by the user
    data.dir <- "raw_data_directory"
    
    if (!dir.exists(data.dir)) {
      stop(paste("Error: Input directory '", data.dir, "' does not exist in the current working directory.", sep = ""))
    }
    
    # --- Read raw 10x data into R ---
    message("Reading raw 10x data...")
    mbrainSub_2 <- Read10xRaw(data.dir)
    
    # Assign to mbrainSub to match the documented workflow variables
    mbrainSub <- mbrainSub_2
    
    # --- Evaluate and choose an appropriate background cutoff ---
    message("Evaluating background cutoff...")
    check_cutoff <- CheckBackgroundCutoff(mbrainSub)
    
    # Display summary table and recommended cutoff
    print(check_cutoff\$summary_table)
    print(check_cutoff\$recommended_cutoff)
    
    # Save background cutoff evaluation results
    write.csv(check_cutoff\$summary_table, file = "background_cutoff_summary.csv", row.names = FALSE)
    writeLines(as.character(check_cutoff\$recommended_cutoff), con = "recommended_cutoff.txt")
    
    # --- Run CB2 to distinguish real cells from empty droplets ---
    message("Running CB2 to identify real cells...")
    CBOut <- CB2FindCell(mbrainSub, FDR_threshold = 0.01, lower = 100, Ncores = 2)
    
    # Save the full CB2 output object
    saveRDS(CBOut, file = "CBOut.rds")
    
    # --- Extract the real cell matrix and filter out damaged cells ---
    message("Extracting real cell matrix and filtering mitochondrial genes...")
    RealCell <- GetCellMat(CBOut, MTfilter = 0.25)
    
    # Save the filtered real cell matrix
    saveRDS(RealCell, file = "RealCell_matrix.rds")
    
    # Optionally save in 10x format if DropletUtils is available
    if (requireNamespace("DropletUtils", quietly = TRUE)) {
      message("Saving filtered matrix in 10x format...")
      DropletUtils::write10xCounts(path = "filtered_cells_10x", x = RealCell, overwrite = TRUE)
    }
    
    message("Pipeline completed successfully. Outputs saved to the current working directory.")

    writeLines(c(
        '"BIOC_SCCB2_DETAILED_CB2_PIPELINE":',
        paste0('        sccb2: ', as.character(packageVersion("sccb2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detailed_cb2_pipeline.csv versions.yml
    """
}

workflow BIOC_SCCB2_DETAILED_CB2_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_data_directory ] ]

    main:
    BIOC_SCCB2_DETAILED_CB2_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SCCB2_DETAILED_CB2_PIPELINE.out.tables
    plots    = BIOC_SCCB2_DETAILED_CB2_PIPELINE.out.plots
    objects  = BIOC_SCCB2_DETAILED_CB2_PIPELINE.out.objects
    versions = BIOC_SCCB2_DETAILED_CB2_PIPELINE.out.versions
}
