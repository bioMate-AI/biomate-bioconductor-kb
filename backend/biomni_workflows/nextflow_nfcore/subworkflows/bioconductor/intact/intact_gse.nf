#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INTACT — intact_gse
// Perform gene set enrichment estimation and inference using integrated TWAS scan z-scores and colocalization probabilities.
// Input: gene_data, gene_sets
// Container: quay.io/biocontainers/bioconductor-intact:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INTACT, jsonlite
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run INTACT::intactGSE to estimate enrichment parameters, standard errors, z-scores, and p-values for each gene set

nextflow.enable.dsl = 2

process BIOC_INTACT_INTACT_GSE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(INTACT)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Inputs from Working Directory
    # -----------------------------------------------------------------------------
    
    # Read gene_data (expected as CSV or RDS)
    if (file.exists("gene_data.csv")) {
      simdat <- read.csv("gene_data.csv", stringsAsFactors = FALSE)
    } else if (file.exists("gene_data.rds")) {
      simdat <- readRDS("gene_data.rds")
    } else {
      stop("Error: Required input file 'gene_data.csv' or 'gene_data.rds' not found in the working directory.")
    }
    
    # Validate gene_data columns
    required_cols <- c("gene", "GLCP", "TWAS_z")
    missing_cols <- setdiff(required_cols, colnames(simdat))
    if (length(missing_cols) > 0) {
      stop(paste("Error: gene_data is missing required columns:", paste(missing_cols, collapse = ", ")))
    }
    
    # Read gene_sets (expected as RDS or JSON)
    if (file.exists("gene_sets.rds")) {
      gene_set_list <- readRDS("gene_sets.rds")
    } else if (file.exists("gene_sets.json")) {
      if (!requireNamespace("jsonlite", quietly = TRUE)) {
        stop("Error: jsonlite package is required to read 'gene_sets.json'. Please provide 'gene_sets.rds' or install jsonlite.")
      }
      gene_set_list <- jsonlite::read_json("gene_sets.json", simplifyVector = TRUE)
    } else {
      stop("Error: Required input file 'gene_sets.rds' or 'gene_sets.json' not found in the working directory.")
    }
    
    # Validate gene_sets format
    if (!is.list(gene_set_list) || is.null(names(gene_set_list))) {
      stop("Error: gene_sets must be a named list.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Run INTACT-GSE Analysis (Documented Workflow)
    # -----------------------------------------------------------------------------
    
    # Run 1: Default settings
    message("Running INTACT::intactGSE with default settings...")
    gse_results_default <- INTACT::intactGSE(gene_data = simdat, gene_sets = gene_set_list)
    
    # Run 2: Step prior settings
    message("Running INTACT::intactGSE with step prior settings...")
    gse_results_step <- INTACT::intactGSE(gene_data = simdat, prior_fun = INTACT::step, t = 0.45, gene_sets = gene_set_list)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save results as CSV tables
    write.csv(gse_results_default, "intact_gse_results_default.csv", row.names = FALSE)
    write.csv(gse_results_step, "intact_gse_results_step.csv", row.names = FALSE)
    
    # Save results as RDS objects for downstream R utility
    saveRDS(gse_results_default, "intact_gse_results_default.rds")
    saveRDS(gse_results_step, "intact_gse_results_step.rds")
    
    message("Workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_INTACT_INTACT_GSE":',
        paste0('    INTACT: ', as.character(packageVersion('INTACT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intact_gse.csv versions.yml
    """
}

workflow BIOC_INTACT_INTACT_GSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_data, gene_sets ] ]

    main:
    BIOC_INTACT_INTACT_GSE(ch_input)

    emit:
    tables   = BIOC_INTACT_INTACT_GSE.out.tables
    plots    = BIOC_INTACT_INTACT_GSE.out.plots
    objects  = BIOC_INTACT_INTACT_GSE.out.objects
    versions = BIOC_INTACT_INTACT_GSE.out.versions
}
