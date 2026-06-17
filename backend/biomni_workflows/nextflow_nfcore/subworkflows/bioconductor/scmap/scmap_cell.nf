#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scmap — scmap_cell
// Project query single-cell RNA-seq data onto individual reference cells and optionally annotate them using reference cluster labels.
// Input: yan, ann
// Container: quay.io/biocontainers/bioconductor-scmap:1.32.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scmap
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create SingleCellExperiment object and preprocess
//  * 2. [Core Analysis] Feature selection using selectFeatures
//  * 3. [Core Analysis] Reference cell indexing using indexCell
//  * 4. [Core Analysis] Projection using scmapCell
//  * 5. [Core Analysis] Cluster annotation using scmapCell2Cluster
//  * 6. [Visualization & Output] Visualization using getSankey

nextflow.enable.dsl = 2

process BIOC_SCMAP_SCMAP_CELL {
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
    .bm_deps <- c("SingleCellExperiment", "scmap", "SummarizedExperiment")
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
                library(SummarizedExperiment)
library(scmap)
        
        # -----------------------------------------------------------------------------
        # Stage 1: Read User Input and Preprocess
        # -----------------------------------------------------------------------------
        
        # Helper function to robustly read the 'yan' matrix
        read_yan <- function() {
          if (file.exists("yan.rds")) {
            return(readRDS("yan.rds"))
          } else if (file.exists("yan.csv")) {
            return(as.matrix(read.csv("yan.csv", row.names = 1, check.names = FALSE)))
          } else if (file.exists("yan.tsv")) {
            return(as.matrix(read.delim("yan.tsv", row.names = 1, check.names = FALSE)))
          } else if (file.exists("yan")) {
            return(as.matrix(read.table("yan", header = TRUE, row.names = 1, check.names = FALSE)))
          } else {
            stop("Error: 'yan' file not found in the working directory.")
          }
        }
        
        # Helper function to robustly read the 'ann' data frame
        read_ann <- function() {
          if (file.exists("ann.rds")) {
            return(readRDS("ann.rds"))
          } else if (file.exists("ann.csv")) {
            return(read.csv("ann.csv", row.names = 1, check.names = FALSE))
          } else if (file.exists("ann.tsv")) {
            return(read.delim("ann.tsv", row.names = 1, check.names = FALSE))
          } else if (file.exists("ann")) {
            return(read.table("ann", header = TRUE, row.names = 1, check.names = FALSE))
          } else {
            stop("Error: 'ann' file not found in the working directory.")
          }
        }
        
        yan <- read_yan()
        ann <- read_ann()
        
        # Construct SingleCellExperiment object and preprocess as documented
        sce <- SingleCellExperiment(assays = list(normcounts = as.matrix(yan)), colData = ann)
        logcounts(sce) <- log2(normcounts(sce) + 1)
        rowData(sce)\$feature_symbol <- rownames(sce)
        sce <- sce[!duplicated(rownames(sce)), ]
        
        # -----------------------------------------------------------------------------
        # Stage 2: Feature Selection
        # -----------------------------------------------------------------------------
        sce <- selectFeatures(sce, suppress_plot = TRUE)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Reference Cell Indexing
        # -----------------------------------------------------------------------------
        set.seed(1)
        sce <- indexCell(sce)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Projection using scmapCell
        # -----------------------------------------------------------------------------
        scmapCell_results <- scmapCell(
          sce, 
          list(
            yan = metadata(sce)\$scmap_cell_index
          )
        )
        
        # -----------------------------------------------------------------------------
        # Stage 5: Cluster Annotation
        # -----------------------------------------------------------------------------
        scmapCell_clusters <- scmapCell2Cluster(
          scmapCell_results, 
          list(
            as.character(colData(sce)\$cell_type1)
          )
        )
        
        # -----------------------------------------------------------------------------
        # Stage 6: Visualization
        # -----------------------------------------------------------------------------
        # The plot() call on a googleVis object is removed to prevent hanging in headless environments.
        # The Sankey diagram is saved as an HTML file in the Save Outputs section.
        
        # -----------------------------------------------------------------------------
        # Save Outputs
        # -----------------------------------------------------------------------------
        
        # Save the processed SingleCellExperiment object
        saveRDS(sce, "processed_sce.rds")
        
        # Save the scmapCell projection results
        saveRDS(scmapCell_results, "scmapCell_results.rds")
        
        # Save the scmapCell cluster annotation results
        saveRDS(scmapCell_clusters, "scmapCell_clusters.rds")
        
        # Export the cluster assignments as a CSV table
        output_labels <- data.frame(
          Cell = rownames(colData(sce)),
          Original_Cell_Type = colData(sce)\$cell_type1,
          Assigned_Cluster = scmapCell_clusters\$scmap_cluster_labs[,"yan"],
          Similarity = scmapCell_clusters\$scmap_cluster_siml[,"yan"],
          Combined_Labs = scmapCell_clusters\$combined_labs,
          stringsAsFactors = FALSE
        )
        write.csv(output_labels, "scmap_cell_assignments.csv", row.names = FALSE)
        
        # Save the Sankey diagram as an HTML file (since getSankey returns a googleVis object)
        sankey_gvis <- getSankey(
          colData(sce)\$cell_type1,
          scmapCell_clusters\$scmap_cluster_labs[,"yan"],
          plot_height = 400
        )
        writeLines(sankey_gvis\$html\$chart, "sankey_plot.html")

    writeLines(c(
        '"BIOC_SCMAP_SCMAP_CELL":',
        paste0('    scmap: ', as.character(packageVersion('scmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmap_cell.csv versions.yml
    """
}

workflow BIOC_SCMAP_SCMAP_CELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ yan, ann ] ]

    main:
    BIOC_SCMAP_SCMAP_CELL(ch_input)

    emit:
    tables   = BIOC_SCMAP_SCMAP_CELL.out.tables
    plots    = BIOC_SCMAP_SCMAP_CELL.out.plots
    objects  = BIOC_SCMAP_SCMAP_CELL.out.objects
    versions = BIOC_SCMAP_SCMAP_CELL.out.versions
}
