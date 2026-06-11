#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scmap — scmap_cluster
// Project query single-cell RNA-seq data onto reference cell-type clusters to assign cell-type labels.
// Input: yan, ann
// Container: quay.io/biocontainers/bioconductor-scmap:1.32.0--r45ha27e39d_0
// R packages: googlevis, scmap, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scmap
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create SingleCellExperiment object and preprocess
//  * 2. [Core Analysis] Feature selection using selectFeatures
//  * 3. [Core Analysis] Reference indexing using indexCluster
//  * 4. [Core Analysis] Projection using scmapCluster
//  * 5. [Visualization & Output] Visualization using getSankey

nextflow.enable.dsl = 2

process BIOC_SCMAP_SCMAP_CLUSTER {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("googlevis", "scmap", "SingleCellExperiment")
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
    library(scmap)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input and Preprocess
    # -----------------------------------------------------------------------------
    
    # Helper function to robustly load user input files (RDS, CSV, or TSV)
    load_input_file <- function(base_name) {
      rds_file <- paste0(base_name, ".rds")
      csv_file <- paste0(base_name, ".csv")
      tsv_file <- paste0(base_name, ".txt")
      
      if (file.exists(rds_file)) {
        return(readRDS(rds_file))
      } else if (file.exists(csv_file)) {
        return(read.csv(csv_file, row.names = 1, check.names = FALSE))
      } else if (file.exists(tsv_file)) {
        return(read.table(tsv_file, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
      } else if (file.exists(base_name)) {
        # Try reading the file directly if no extension was appended but file exists
        try_rds <- try(readRDS(base_name), silent = TRUE)
        if (!inherits(try_rds, "try-error")) return(try_rds)
        
        try_csv <- try(read.csv(base_name, row.names = 1, check.names = FALSE), silent = TRUE)
        if (!inherits(try_csv, "try-error")) return(try_csv)
        
        stop(paste("File found but could not be parsed as RDS or CSV:", base_name))
      } else {
        stop(paste("Required input file not found in the working directory:", base_name))
      }
    }
    
    # Load the exact user inputs
    yan <- load_input_file("yan")
    ann <- load_input_file("ann")
    
    # Ensure yan is a matrix
    yan <- as.matrix(yan)
    
    # Create SingleCellExperiment object and preprocess
    sce <- SingleCellExperiment(assays = list(normcounts = as.matrix(yan)), colData = ann)
    logcounts(sce) <- log2(normcounts(sce) + 1)
    rowData(sce)\$feature_symbol <- rownames(sce)
    sce <- sce[!duplicated(rownames(sce)), ]
    
    # -----------------------------------------------------------------------------
    # Stage 2: Feature selection using selectFeatures
    # -----------------------------------------------------------------------------
    sce <- selectFeatures(sce, suppress_plot = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Reference indexing using indexCluster
    # -----------------------------------------------------------------------------
    sce <- indexCluster(sce)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Projection using scmapCluster
    # -----------------------------------------------------------------------------
    scmapCluster_results <- scmapCluster(
      projection = sce, 
      index_list = list(
        yan = metadata(sce)\$scmap_cluster_index
      )
    )
    
    # -----------------------------------------------------------------------------
    # Stage 5: Visualization using getSankey and Saving Outputs
    # -----------------------------------------------------------------------------
    
    # Save the main results to RDS
    saveRDS(scmapCluster_results, "scmap_cluster_results.rds")
    saveRDS(sce, "sce_processed.rds")
    
    # Save projection results as a CSV table
    results_df <- data.frame(
      Cell = colnames(sce),
      Actual_Cell_Type = colData(sce)\$cell_type1,
      Projected_Cell_Type = scmapCluster_results\$scmap_cluster_labs[,'yan'],
      Similarity = scmapCluster_results\$scmap_cluster_siml[,'yan'],
      Combined_Labs = scmapCluster_results\$combined_labs,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "scmap_cluster_predictions.csv", row.names = FALSE)
    
    # Generate and save the Sankey diagram
    sankey_gvis <- getSankey(
      colData(sce)\$cell_type1,
      scmapCluster_results\$scmap_cluster_labs[,'yan'],
      plot_height = 400
    )
    
    # Save the interactive Sankey plot as an HTML file
    if (!is.null(sankey_gvis\$html\$chart)) {
      cat(sankey_gvis\$html\$chart, file = "sankey_plot.html")
    }
    
    # Execute the documented plot call (wrapped in tryCatch to prevent headless environment failures)
    tryCatch({
      pdf("sankey_plot.pdf", width = 8, height = 6)
      plot(
        getSankey(
          colData(sce)\$cell_type1,
          scmapCluster_results\$scmap_cluster_labs[,'yan'],
          plot_height = 400
        )
      )
      dev.off()
    }, error = function(e) {
      warning("Could not plot Sankey to PDF (this is normal in non-interactive/headless environments): ", e\$message)
    })

    writeLines(c(
        '"BIOC_SCMAP_SCMAP_CLUSTER":',
        paste0('    scmap: ', as.character(packageVersion('scmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmap_cluster.csv versions.yml
    """
}

workflow BIOC_SCMAP_SCMAP_CLUSTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ yan, ann ] ]

    main:
    BIOC_SCMAP_SCMAP_CLUSTER(ch_input)

    emit:
    tables   = BIOC_SCMAP_SCMAP_CLUSTER.out.tables
    plots    = BIOC_SCMAP_SCMAP_CLUSTER.out.plots
    objects  = BIOC_SCMAP_SCMAP_CLUSTER.out.objects
    versions = BIOC_SCMAP_SCMAP_CLUSTER.out.versions
}
