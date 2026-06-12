#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Harman — transcriptomic_microarray
// Correct batch effects in log2-transformed microarray expression data and reconstruct the corrected matrix.
// Input: olf.data, olf.info
// Container: quay.io/biocontainers/bioconductor-harman:1.38.0--r45ha27e39d_0
// R packages: bladderbatch, Harman, harmandata, limma, msmsEDA, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: Harman
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs
//  * 2. [Visualization & Output] Run Harman to find and correct batch effects
//  * 3. [Visualization & Output] Inspect results and save outputs
//  * 4. [Visualization & Output] Reconstruct the corrected data matrix
//  * 5. [Visualization & Output] Reconstruct original data and verify reconstruction

nextflow.enable.dsl = 2

process BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("bladderbatch", "Harman", "harmandata", "limma", "msmsEDA", "RColorBrewer")
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
    library(Harman)
    
    # Helper function to read inputs robustly (handles RDS, TSV, or CSV)
    read_input <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file missing:", file_path))
      }
      
      # Try reading as RDS
      obj <- tryCatch(readRDS(file_path), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try reading as table (tab/space delimited)
      obj <- tryCatch(read.table(file_path, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try reading as CSV
      obj <- tryCatch(read.csv(file_path, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      stop(paste("Failed to parse file:", file_path))
    }
    
    # --- Read User Inputs ---
    olf.data <- read_input("olf.data")
    olf.info <- read_input("olf.info")
    
    # Ensure correct data types and structures
    olf.data <- as.matrix(olf.data)
    olf.info\$Treatment <- as.factor(olf.info\$Treatment)
    olf.info\$Batch <- as.factor(olf.info\$Batch)
    
    # --- Run Harman to find and correct batch effects ---
    olf.harman <- harman(olf.data, expt=olf.info\$Treatment, batch=olf.info\$Batch, limit=0.95)
    
    # --- Inspect results and save outputs ---
    # Save diagnostic plots to PDF
    pdf("harman_diagnostics.pdf", width = 7, height = 7)
    plot(olf.harman)
    arrowPlot(olf.harman, main='Arrowplot of correction')
    dev.off()
    
    # Save summary text to file
    sink("harman_summary.txt")
    summary(olf.harman)
    sink()
    
    # Save the harmanresults object
    saveRDS(olf.harman, "olf_harman_results.rds")
    
    # --- Reconstruct the corrected data matrix ---
    olf.data.corrected <- reconstructData(olf.harman)
    
    # Save corrected data matrix
    write.csv(olf.data.corrected, "olf_data_corrected.csv", row.names = TRUE)
    saveRDS(olf.data.corrected, "olf_data_corrected.rds")
    
    # --- Reconstruct original data and verify reconstruction ---
    olf.data.remade <- reconstructData(olf.harman, this='original')
    verification <- all.equal(as.matrix(olf.data), olf.data.remade)
    
    # Save verification result
    writeLines(as.character(verification), "reconstruction_verification.txt")

    writeLines(c(
        '"BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY":',
        paste0('    Harman: ', as.character(packageVersion('Harman')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcriptomic_microarray.csv versions.yml
    """
}

workflow BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ olf.data, olf.info ] ]

    main:
    BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY(ch_input)

    emit:
    tables   = BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY.out.tables
    plots    = BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY.out.plots
    objects  = BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY.out.objects
    versions = BIOC_HARMAN_TRANSCRIPTOMIC_MICROARRAY.out.versions
}
