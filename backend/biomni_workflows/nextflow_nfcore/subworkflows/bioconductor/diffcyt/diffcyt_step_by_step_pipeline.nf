#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffcyt — diffcyt_step_by_step_pipeline
// Run the individual step-by-step functions of the diffcyt pipeline for custom control over data transformation, clustering, and feature calculation.
// Input: d_flowSet, experiment_info, marker_info
// Container: quay.io/biocontainers/bioconductor-diffcyt:1.30.0--r45hdfd78af_0
// R packages: diffcyt, flowCore
// Bioconductor: 3.20 | R: 4.4
// Requires: diffcyt, flowCore
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Set Up Design and Contrast Matrices
//  * 3. [Visualization & Output] Run Step-by-Step diffcyt Pipeline
//  * 4. [Visualization & Output] Save Outputs and Generate Plots

nextflow.enable.dsl = 2

process BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE {
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
    .bm_deps <- c("diffcyt", "flowCore")
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
    library(diffcyt)
    library(flowCore)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Read d_flowSet (expected to be saved as an RDS file)
    if (file.exists("d_flowSet.rds")) {
      d_flowSet <- readRDS("d_flowSet.rds")
    } else {
      stop("Error: 'd_flowSet.rds' not found in the working directory.")
    }
    
    # Read experiment_info (can be RDS or CSV)
    if (file.exists("experiment_info.rds")) {
      experiment_info <- readRDS("experiment_info.rds")
    } else if (file.exists("experiment_info.csv")) {
      experiment_info <- read.csv("experiment_info.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: 'experiment_info' (RDS or CSV) not found in the working directory.")
    }
    
    # Read marker_info (can be RDS or CSV)
    if (file.exists("marker_info.rds")) {
      marker_info <- readRDS("marker_info.rds")
    } else if (file.exists("marker_info.csv")) {
      marker_info <- read.csv("marker_info.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: 'marker_info' (RDS or CSV) not found in the working directory.")
    }
    
    # Ensure marker_class is a factor with correct levels
    if ("marker_class" %in% colnames(marker_info)) {
      marker_info\$marker_class <- factor(marker_info\$marker_class, levels = c("type", "state", "none"))
    }
    
    # ==========================================
    # --- Set Up Design and Contrast Matrices ---
    # ==========================================
    
    # Dynamically determine design columns based on available metadata
    cols_design <- intersect(c("group_id", "patient_id"), colnames(experiment_info))
    if (length(cols_design) == 0) {
      cols_design <- setdiff(colnames(experiment_info), "sample_id")
    }
    
    design <- createDesignMatrix(experiment_info, cols_design = cols_design)
    
    # Create contrast matrix (comparing the second column/level to the baseline)
    contrast_vec <- rep(0, ncol(design))
    if (ncol(design) >= 2) {
      contrast_vec[2] <- 1
    } else {
      contrast_vec[1] <- 1
    }
    contrast <- createContrast(contrast_vec)
    
    # ==========================================
    # --- Run Step-by-Step diffcyt Pipeline ---
    # ==========================================
    
    # Prepare data
    d_se <- prepareData(d_flowSet, experiment_info, marker_info)
    
    # Transform data
    d_se <- transformData(d_se)
    
    # Generate clusters
    d_se <- generateClusters(d_se, seed_clustering = 123)
    
    # Calculate cluster cell counts
    d_counts <- calcCounts(d_se)
    
    # Calculate cluster medians
    d_medians <- calcMedians(d_se)
    
    # Test for differential abundance (DA) of clusters
    res_DA <- testDA_edgeR(d_counts, design, contrast)
    
    # display table of results for top DA clusters
    top_DA_table <- topTable(res_DA, format_vals = TRUE)
    print("Top DA Clusters:")
    print(top_DA_table)
    
    # Test for differential states (DS) within clusters
    res_DS <- testDS_limma(d_counts, d_medians, design, contrast, plot = FALSE)
    
    # display table of results for top DS cluster-marker combinations
    top_DS_table <- topTable(res_DS, format_vals = TRUE)
    print("Top DS Cluster-Marker Combinations:")
    print(top_DS_table)
    
    # ==========================================
    # --- Save Outputs and Generate Plots ---
    # ==========================================
    
    # Save RDS objects
    saveRDS(d_se, "d_se.rds")
    saveRDS(d_counts, "d_counts.rds")
    saveRDS(d_medians, "d_medians.rds")
    saveRDS(res_DA, "res_DA.rds")
    saveRDS(res_DS, "res_DS.rds")
    
    # Save full results tables as CSV
    write.csv(as.data.frame(topTable(res_DA, all = TRUE)), "res_DA_all.csv", row.names = FALSE)
    write.csv(as.data.frame(topTable(res_DS, all = TRUE)), "res_DS_all.csv", row.names = FALSE)
    
    # Reconstruct wrapper-like output structures for plotting
    out_DA <- list(res = res_DA, d_se = d_se, d_counts = d_counts)
    out_DS <- list(res = res_DS, d_se = d_se, d_counts = d_counts, d_medians = d_medians)
    
    # Generate and save DA Heatmap
    pdf("heatmap_DA.pdf", width = 10, height = 8)
    tryCatch({
      plotHeatmap(out_DA, analysis_type = "DA")
    }, error = function(e) {
      message("Could not generate DA heatmap: ", e\$message)
    })
    dev.off()
    
    # Generate and save DS Heatmap
    pdf("heatmap_DS.pdf", width = 12, height = 10)
    tryCatch({
      plotHeatmap(out_DS, analysis_type = "DS")
    }, error = function(e) {
      message("Could not generate DS heatmap: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE":',
        paste0('    diffcyt: ', as.character(packageVersion('diffcyt')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffcyt_step_by_step_pipeline.csv versions.yml
    """
}

workflow BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ d_flowSet, experiment_info, marker_info ] ]

    main:
    BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE.out.tables
    plots    = BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE.out.plots
    objects  = BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE.out.objects
    versions = BIOC_DIFFCYT_DIFFCYT_STEP_BY_STEP_PIPELINE.out.versions
}
