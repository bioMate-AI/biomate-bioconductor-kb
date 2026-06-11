#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: famat — famat_analysis_and_visualization
// Perform integrated pathway enrichment, interaction network analysis, and GO enrichment on gene and metabolite lists, and visualize the results in a Shiny app.
// Input: genes, meta
// Container: quay.io/biocontainers/bioconductor-famat:1.20.3--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: famat, mgcv
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run pathway enrichment analysis for KEGG, Reactome, and WikiPathways using path_enrich
//  * 2. [Core Analysis] Extract direct interactions and calculate centrality using interactions
//  * 3. [Core Analysis] Complete the data with GO term enrichment and pathway filtering using compl_data
//  * 4. [Core Analysis] Launch the interactive Shiny application using rshiny

nextflow.enable.dsl = 2

process BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20"

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
    .bm_deps <- c("famat", "mgcv")
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
    library(famat)
    library(mgcv)
    
    # Read user input files from the working directory
    if (file.exists("genes")) {
      genes <- readLines("genes")
    } else if (file.exists("genes.txt")) {
      genes <- readLines("genes.txt")
    } else {
      stop("Error: Input file 'genes' or 'genes.txt' not found in the working directory.")
    }
    genes <- unique(trimws(genes[genes != ""]))
    
    if (file.exists("meta")) {
      meta <- readLines("meta")
    } else if (file.exists("meta.txt")) {
      meta <- readLines("meta.txt")
    } else {
      stop("Error: Input file 'meta' or 'meta.txt' not found in the working directory.")
    }
    meta <- unique(trimws(meta[meta != ""]))
    
    # Retrieve the required reference dataset without using data()
    all_compounds_chebi <- get("all_compounds_chebi", envir = as.environment("package:famat"))
    
    # Stage 1: Run pathway enrichment analysis for KEGG, Reactome, and WikiPathways
    message("Running pathway enrichment for KEGG...")
    listk <- path_enrich("KEGG", meta, genes)
    
    message("Running pathway enrichment for Reactome...")
    listr <- path_enrich("REAC", meta, genes)
    
    message("Running pathway enrichment for WikiPathways...")
    listw <- path_enrich("WP", meta, genes)
    
    # Stage 2: Extract direct interactions and calculate centrality
    message("Extracting interactions...")
    interactions_result <- interactions(listk, listr, listw)
    
    # Stage 3: Complete the data with GO term enrichment and pathway filtering
    message("Completing data with GO enrichment and pathway filtering...")
    compl_data_result <- compl_data(interactions_result)
    
    # Save meaningful results to files
    message("Saving results...")
    saveRDS(listk, "path_enrich_kegg.rds")
    saveRDS(listr, "path_enrich_reac.rds")
    saveRDS(listw, "path_enrich_wp.rds")
    saveRDS(interactions_result, "interactions_result.rds")
    saveRDS(compl_data_result, "compl_data_result.rds")
    
    # Export data frames from compl_data_result to CSV if available
    if (is.list(compl_data_result)) {
      for (name in names(compl_data_result)) {
        val <- compl_data_result[[name]]
        if (is.data.frame(val)) {
          write.csv(val, paste0("compl_data_", name, ".csv"), row.names = FALSE)
        } else if (is.list(val)) {
          for (subname in names(val)) {
            subval <- val[[subname]]
            if (is.data.frame(subval)) {
              write.csv(subval, paste0("compl_data_", name, "_", subname, ".csv"), row.names = FALSE)
            }
          }
        }
      }
    }
    
    # Stage 4: Launch the interactive Shiny application
    if (interactive()) {
      message("Launching interactive Shiny application...")
      rshiny(compl_data_result)
    } else {
      message("Non-interactive execution: skipping interactive Shiny app launch.")
      message("You can launch the app later using: famat::rshiny(readRDS('compl_data_result.rds'))")
    }

    writeLines(c(
        '"BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION":',
        paste0('    famat: ', as.character(packageVersion('famat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_famat_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes, meta ] ]

    main:
    BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_FAMAT_FAMAT_ANALYSIS_AND_VISUALIZATION.out.versions
}
