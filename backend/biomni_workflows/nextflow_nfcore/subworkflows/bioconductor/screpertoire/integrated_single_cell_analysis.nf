#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRepertoire — integrated_single_cell_analysis
// Integrate processed TCR/BCR clonal data with single-cell RNA-seq objects (Seurat or SingleCellExperiment) to analyze clonal phenotypes and spatial distribution 
// Input: combined.TCR, scRep_example
// Container: quay.io/biocontainers/bioconductor-screpertoire:2.2.0--r44he5774e6_0
// R packages: Seurat, SingleCellExperiment, circlize, ggplot2, ggraph, scRepertoire, scales
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SingleCellExperiment, circlize, ggplot2, ggraph, scRepertoire, scales
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Files
//  * 2. [Visualization & Output] Exclude VDJ genes from highly variable features
//  * 3. [Visualization & Output] Merge clonal data into the single-cell objects
//  * 4. [Visualization & Output] Visualize clonal expansion on UMAP/tSNE
//  * 5. [Visualization & Output] Map clonal sharing between clusters
//  * 6. [Visualization & Output] Highlight specific clones
//  * 7. [Visualization & Output] Analyze cluster occupancy
//  * 8. [Visualization & Output] Track clones across categorical variables
//  * 9. [Visualization & Output] Generate chord diagrams of clonal sharing
//  * 10. [Visualization & Output] Calculate STARTRAC diversity indices
//  * 11. [Visualization & Output] Calculate clonal bias

nextflow.enable.dsl = 2

process BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("Seurat", "SingleCellExperiment", "circlize", "ggplot2", "ggraph", "scRepertoire", "scales")
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
                    suppressPackageStartupMessages({
                      library(scRepertoire)
                      library(Seurat)
                      library(ggplot2)
                      library(ggraph)
                      library(circlize)
                      library(scales)
                    })
                    
                    # -------------------------------------------------------------------------
                    # --- Load User Input Files ---
                    # -------------------------------------------------------------------------
                    message("Loading input files from the working directory...")
                    
                    combined_tcr_path <- "combined.TCR"
                    if (!file.exists(combined_tcr_path)) {
                      combined_tcr_path <- "combined.TCR.rds"
                    }
                    if (!file.exists(combined_tcr_path)) {
                      stop("Error: 'combined.TCR' or 'combined.TCR.rds' not found in the working directory.")
                    }
                    combined.TCR <- readRDS(combined_tcr_path)
                    
                    sc_example_path <- "scRep_example"
                    if (!file.exists(sc_example_path)) {
                      sc_example_path <- "scRep_example.rds"
                    }
                    if (!file.exists(sc_example_path)) {
                      stop("Error: 'scRep_example' or 'scRep_example.rds' not found in the working directory.")
                    }
                    scRep_example <- readRDS(sc_example_path)
                    
                    # Create SingleCellExperiment companion object
                    sce <- Seurat::as.SingleCellExperiment(scRep_example)
                    
                    # Add metadata variables
                    scRep_example\$Patient <- substr(scRep_example\$orig.ident, 1, 3)
                    scRep_example\$Type <- substr(scRep_example\$orig.ident, 4, 4)
                    
                    # -------------------------------------------------------------------------
                    # --- Exclude VDJ genes from highly variable features ---
                    # -------------------------------------------------------------------------
                    message("Excluding VDJ genes using quietTCRgenes...")
                    scRep_example <- quietTCRgenes(scRep_example)
                    
                    # -------------------------------------------------------------------------
                    # --- Merge clonal data into the single-cell objects ---
                    # -------------------------------------------------------------------------
                    message("Merging clonal data using combineExpression...")
                    sce <- combineExpression(combined.TCR, 
                                             sce, 
                                             cloneCall="gene", 
                                             group.by = "orig.ident", 
                                             proportion = TRUE)
                    
                    scRep_example <- combineExpression(combined.TCR, 
                                                       scRep_example, 
                                                       cloneCall="gene", 
                                                       group.by = "orig.ident", 
                                                       proportion = FALSE, 
                                                       cloneSize=c(Single=1, Small=5, Medium=20, Large=100, Hyperexpanded=500))
                    
                    # Save integrated single-cell objects
                    saveRDS(sce, "sce_integrated.rds")
                    saveRDS(scRep_example, "seurat_integrated.rds")
                    
                    # -------------------------------------------------------------------------
                    # --- Visualize clonal expansion on UMAP/tSNE ---
                    # -------------------------------------------------------------------------
                    message("Generating clonalOverlay plot...")
                    p_overlay <- clonalOverlay(scRep_example, 
                                               reduction = "umap", 
                                               freq.cutpoint = 1, 
                                               bins = 10, 
                                               facet.by = "Patient") + 
                                 guides(color = "none")
                    ggsave("clonal_overlay.pdf", plot = p_overlay, width = 10, height = 8)
                    
                    # -------------------------------------------------------------------------
                    # --- Map clonal sharing between clusters ---
                    # -------------------------------------------------------------------------
                    message("Generating clonalNetwork plot...")
                    p_network <- clonalNetwork(scRep_example, 
                                               reduction = "umap", 
                                               group.by = "seurat_clusters",
                                               filter.clones = NULL,
                                               filter.identity = NULL,
                                               cloneCall = "aa")
                    ggsave("clonal_network.pdf", plot = p_network, width = 10, height = 8)
                    
                    # -------------------------------------------------------------------------
                    # --- Highlight specific clones ---
                    # -------------------------------------------------------------------------
                    message("Highlighting specific clones...")
                    clone_counts <- table(scRep_example\$CTaa)
                    top_clones <- names(sort(clone_counts, decreasing = TRUE))
                    top_clones <- top_clones[1:min(2, length(top_clones))]
                    
                    p_highlight <- highlightClones(scRep_example,
                                                   cloneCall = "aa",
                                                   sequence = top_clones)
                    ggsave("highlight_clones.pdf", plot = p_highlight, width = 10, height = 8)
                    
                    # -------------------------------------------------------------------------
                    # --- Analyze cluster occupancy ---
                    # -------------------------------------------------------------------------
                    message("Generating clonalOccupy plot...")
                    p_occupy <- clonalOccupy(scRep_example, 
                                             x.axis = "seurat_clusters")
                    ggsave("clonal_occupy.pdf", plot = p_occupy, width = 10, height = 8)
                    
                    # -------------------------------------------------------------------------
                    # --- Track clones across categorical variables ---
                    # -------------------------------------------------------------------------
                    message("Generating alluvialClones plot...")
                    p_alluvial <- alluvialClones(scRep_example,
                                                 cloneCall = "aa",
                                                 y.axes = c("Patient", "seurat_clusters", "Type"),
                                                 color = "CTaa")
                    ggsave("alluvial_clones.pdf", plot = p_alluvial, width = 12, height = 8)
                    
                    # -------------------------------------------------------------------------
                    # --- Generate chord diagrams of clonal sharing ---
                    # -------------------------------------------------------------------------
                    message("Generating vizCirclize plot...")
                    pdf("viz_circlize.pdf", width = 8, height = 8)
                    circlize_data <- getCirclize(scRep_example,
                                                 group.by = "seurat_clusters",
                                                 cloneCall = "aa")
                    circlize::chordDiagram(circlize_data)
                    dev.off()
                    
                    # -------------------------------------------------------------------------
                    # --- Calculate STARTRAC diversity indices ---
                    # -------------------------------------------------------------------------
                    message("Calculating StartracDiversity...")
                    startrac_res <- StartracDiversity(scRep_example, 
                                                      type = "Type", 
                                                      sample = "Patient")
                    saveRDS(startrac_res, "startrac_diversity.rds")
                    
                    # -------------------------------------------------------------------------
                    # --- Calculate clonal bias ---
                    # -------------------------------------------------------------------------
                    message("Calculating clonalBias...")
                    p_bias <- clonalBias(scRep_example, 
                                         cloneCall = "aa", 
                                         split.by = "Patient", 
                                         group.by = "seurat_clusters",
                                         n.boots = 10, 
                                         min.expand = 5)
                    ggsave("clonal_bias.pdf", plot = p_bias, width = 10, height = 8)
                    
                    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS":',
        paste0('    scRepertoire: ', as.character(packageVersion('scRepertoire')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_single_cell_analysis.csv versions.yml
    """
}

workflow BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ combined.TCR, scRep_example ] ]

    main:
    BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS.out.tables
    plots    = BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS.out.plots
    objects  = BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS.out.objects
    versions = BIOC_SCREPERTOIRE_INTEGRATED_SINGLE_CELL_ANALYSIS.out.versions
}
