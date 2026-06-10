#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FlowSOM — flowsom_cytometry_clustering
// Perform unsupervised clustering and metaclustering on single-cell cytometry data using FlowSOM, generating cell-to-cluster assignments and visualising the resul
// Input: input.csv
// Container: 2.18.0--r45h01b2380_0
// R packages: flowCore, FlowSOM
// Bioconductor: 3.20 | R: 4.4
// Requires: FlowSOM, flowCore
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("flowCore", "FlowSOM")
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
    library(flowCore)
    library(FlowSOM)
    
    # Set seed for reproducibility
    set.seed(42)
    
    # ==========================================
    # Stage 1: Read and Preprocess Input Data
    # ==========================================
    message("Stage 1: Reading and preprocessing input data...")
    
    # Read the input feature-by-sample matrix
    # Rows = features (markers/channels), Columns = samples (individual cells)
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found.")
    }
    
    input_data <- read.csv("input.csv", row.names = 1, check.names = FALSE)
    
    if (ncol(input_data) < 5 || nrow(input_data) < 2) {
      stop("Input matrix is too small for meaningful FlowSOM clustering.")
    }
    
    # Transpose the matrix so that rows represent cells and columns represent markers
    cell_matrix <- t(as.matrix(input_data))
    
    # Convert the matrix to a flowFrame object as required by FlowSOM
    ff <- flowCore::flowFrame(exprs = cell_matrix)
    
    # Initialize FlowSOM input object (scaling is recommended for cytometry data)
    fSOM <- ReadInput(ff, compensate = FALSE, transform = FALSE, scale = TRUE)
    
    # ==========================================
    # Stage 2: Build Self-Organizing Map (SOM)
    # ==========================================
    message("Stage 2: Building Self-Organizing Map...")
    
    # Dynamically adjust grid size based on the number of cells to avoid overfitting
    n_cells <- nrow(cell_matrix)
    if (n_cells < 100) {
      xdim <- 4
      ydim <- 4
      n_meta <- 4
    } else if (n_cells < 500) {
      xdim <- 6
      ydim <- 6
      n_meta <- 6
    } else {
      xdim <- 7
      ydim <- 7
      n_meta <- 7
    }
    
    # Build the SOM using all available markers/channels
    fSOM <- BuildSOM(fSOM, colsToUse = colnames(ff), xdim = xdim, ydim = ydim)
    
    # ==========================================
    # Stage 3: Build Minimal Spanning Tree (MST)
    # ==========================================
    message("Stage 3: Building Minimal Spanning Tree...")
    fSOM <- BuildMST(fSOM)
    
    # ==========================================
    # Stage 4: Metaclustering
    # ==========================================
    message("Stage 4: Performing metaclustering...")
    
    # Perform consensus metaclustering on the SOM codes
    metaClustering <- as.character(metaClustering_consensus(fSOM\$map\$codes, k = n_meta))
    
    # Map metaclusters back to individual cells
    metaClustering_perCell <- GetMetaclusters(fSOM, metaClustering)
    
    # Store metacluster assignments in the FlowSOM object for downstream plotting
    fSOM\$metaclustering <- metaClustering_perCell
    
    # Extract cell-level cluster and metacluster assignments
    cell_clusters <- GetClusters(fSOM)
    
    # Save assignments to a CSV file
    assignments <- data.frame(
      Cell_ID = rownames(cell_matrix),
      Cluster = cell_clusters,
      Metacluster = metaClustering_perCell,
      stringsAsFactors = FALSE
    )
    write.csv(assignments, "flowsom_assignments.csv", row.names = FALSE)
    message("Saved cell assignments to 'flowsom_assignments.csv'.")
    
    # ==========================================
    # Stage 5: Visualisation and Reporting
    # ==========================================
    message("Stage 5: Generating visualisations...")
    
    # 1. Generate the standard FlowSOMmary PDF report
    tryCatch({
      FlowSOMmary(fsom = fSOM, plotFile = "FlowSOMmary.pdf")
      message("Generated 'FlowSOMmary.pdf'.")
    }, error = function(e) {
      warning("FlowSOMmary generation failed: ", e\$message)
      # Create a dummy PDF to satisfy output requirements if it fails
      pdf("FlowSOMmary.pdf")
      plot.new()
      text(0.5, 0.5, "FlowSOMmary generation failed or was skipped.")
      dev.off()
    })
    
    # 2. Generate a custom MST Star Plot with metacluster backgrounds
    tryCatch({
      pdf("flowsom_mst_stars.pdf", width = 10, height = 10)
      PlotStars(fSOM, backgroundValues = fSOM\$metaclustering)
      dev.off()
      message("Generated 'flowsom_mst_stars.pdf'.")
    }, error = function(e) {
      warning("MST Star Plot generation failed: ", e\$message)
      pdf("flowsom_mst_stars.pdf")
      plot.new()
      text(0.5, 0.5, "MST Star Plot generation failed.")
      dev.off()
    })
    
    message("FlowSOM analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING":',
        paste0('    FlowSOM: ', as.character(packageVersion('FlowSOM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowsom_cytometry_clustering.csv versions.yml
    """
}

workflow BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING.out.tables
    plots    = BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING.out.plots
    objects  = BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING.out.objects
    versions = BIOC_FLOWSOM_FLOWSOM_CYTOMETRY_CLUSTERING.out.versions
}
