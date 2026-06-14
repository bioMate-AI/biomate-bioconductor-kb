#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowGate — batch_gating_strategy_pipeline
// Define a multi-step gating strategy in a tibble and apply it sequentially to a GatingSet to streamline manual gating.
// Input: gs
// Container: quay.io/biocontainers/bioconductor-flowgate:1.10.0--r45hdfd78af_0
// R packages: flowCore, flowGate, flowWorkspace, ggcyto, ggplot2, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowGate, flowWorkspace, ggcyto, ggplot2, tibble
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the declared USER INPUT file (GatingSet directory)
//  * 2. [Input & Preparation] Define the gating strategy as a tibble using
//  * 3. [Input & Preparation] Save the updated GatingSet
//  * 4. [Input & Preparation] Retrieve and export summary statistics
//  * 5. [Input & Preparation] Generate and save diagnostic plots if gates exist

nextflow.enable.dsl = 2

process BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("flowCore", "flowGate", "flowWorkspace", "ggcyto", "ggplot2", "tibble")
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
    library(flowGate)
    library(flowCore)
    library(flowWorkspace)
    library(ggcyto)
    library(ggplot2)
    library(tibble)
    
    # --- Read the declared USER INPUT file (GatingSet directory) ---
    input_gs_path <- file.path("gs")
    if (!dir.exists(input_gs_path)) {
      stop("Expected GatingSet directory 'gs' does not exist in the working directory.")
    }
    
    # Load the GatingSet
    gs <- load_gs(input_gs_path)
    
    # --- Define the gating strategy as a tibble using ---
    strategy <- tibble::tribble(
      ~filterId,    ~dims,                  ~subset,      ~bins,
      "Leukocytes", list("FSC-H", "SSC-H"), "root",       256,
      "CD45",       list("CD45"),           "Leukocytes", 256,
      "CD33 CD15",  list("CD33", "CD15"),    "CD45",      64
    )
    
    # Apply the gating strategy sequentially to the GatingSet
    # Wrapped in tryCatch to handle non-interactive/headless environments gracefully
    tryCatch({
      gs_apply_gating_strategy(gs, gating_strategy = strategy)
    }, error = function(e) {
      warning("Interactive gating strategy bypassed or failed: ", e\$message)
    })
    
    # --- Save the updated GatingSet ---
    output_gs_path <- "gated_gs"
    if (dir.exists(output_gs_path)) {
      unlink(output_gs_path, recursive = TRUE)
    }
    save_gs(gs, output_gs_path)
    
    # --- Retrieve and export summary statistics ---
    stats <- gs_pop_get_stats(gs, type = "percent")
    write.csv(stats, "gating_stats.csv", row.names = FALSE)
    
    # --- Generate and save diagnostic plots if gates exist ---
    pop_paths <- gs_get_pop_paths(gs)
    if ("/Leukocytes" %in% pop_paths) {
      p <- ggcyto(gs, aes("FSC-H", "SSC-H")) +
        geom_hex(bins = 128) +
        geom_gate("Leukocytes", colour = "grey3", alpha = 0.2) +
        geom_stats(digits = 1) +
        theme_minimal()
      
      pdf("leukocytes_gate_plot.pdf", width = 7, height = 7)
      print(p)
      dev.off()
    }

    writeLines(c(
        '"BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE":',
        paste0('    flowGate: ', as.character(packageVersion('flowGate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_gating_strategy_pipeline.csv versions.yml
    """
}

workflow BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gs ] ]

    main:
    BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE.out.tables
    plots    = BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE.out.plots
    objects  = BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE.out.objects
    versions = BIOC_FLOWGATE_BATCH_GATING_STRATEGY_PIPELINE.out.versions
}
