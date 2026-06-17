#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nipalsMCIA — single_cell_cite_seq_mcia
// Run MCIA on single-cell multi-omics (GEX and ADT) data to analyze joint embeddings and cell-type specific trends.
// Input: obj, metadata_sc
// Container: quay.io/biocontainers/bioconductor-nipalsmcia:1.8.1--r45hdfd78af_0
// R packages: ComplexHeatmap, MultiAssayExperiment, Seurat, SingleCellExperiment, nipalsMCIA, scales
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, MultiAssayExperiment, Seurat, SingleCellExperiment, nipalsMCIA, scales
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract normalized matrices for GEX and ADT from Seurat object
//  * 2. [Core Analysis] Combine matrices into a list and convert to a MultiAssayExperiment (MAE)
//  * 3. [Core Analysis] Run MCIA using nipals_multiblock() with block-level preprocessing set to "largest_sv"
//  * 4. [Visualization & Output] Visualize eigenvalues, global scores, heatmaps, and loadings

nextflow.enable.dsl = 2

process BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("ComplexHeatmap", "MultiAssayExperiment", "Seurat", "SingleCellExperiment", "nipalsMCIA", "scales")
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
        library(Seurat)
        library(MultiAssayExperiment)
        library(nipalsMCIA)
        library(scales)
        library(ComplexHeatmap)
        
        # 1. Read user input files from the working directory
        # Expecting 'obj.rds' (Seurat object) and 'metadata_sc.csv' (metadata data frame)
        if (!file.exists("obj.rds") || !file.exists("metadata_sc.csv")) {
          stop("Required input files 'obj.rds' and/or 'metadata_sc.csv' are missing from the working directory.")
        }
        
        obj <- readRDS("obj.rds")
        metadata_sc <- read.csv("metadata_sc.csv", row.names = 1)
        
        # 2. Extract normalized matrices for GEX and ADT from Seurat object
        data_rna <- GetAssayData(object = obj, layer = "data", assay = "RNA")[VariableFeatures(object = obj), ]
        data_rna <- as.matrix(data_rna)
        data_rna <- t(data_rna)
        
        data_adt <- GetAssayData(object = obj, layer = "data", assay = "ADT")
        data_adt <- as.matrix(data_adt)
        data_adt <- t(data_adt)
        
        # 3. Combine matrices into a list and convert to a MultiAssayExperiment (MAE)
        data_blocks_sc <- list(mrna = data_rna, adt = data_adt)
        data_blocks_sc_mae <- MultiAssayExperiment::MultiAssayExperiment(
          lapply(data_blocks_sc, function(x) SingleCellExperiment::SingleCellExperiment(t(as.matrix(x)))),
          colData = metadata_sc
        )
        
        # 4. Run MCIA using nipals_multiblock()
        mcia_results_sc <- nipals_multiblock(
          data_blocks = data_blocks_sc_mae,
          col_preproc_method = "colprofile",
          block_preproc_method = "largest_sv",
          num_PCs = 10,
          tol = 1e-9,
          deflationMethod = "global",
          plots = "none"
        )
        
        # Save the primary MCIA results object
        saveRDS(mcia_results_sc, "mcia_results_sc.rds")
        
        # Export global scores and loadings to CSV
        if (.hasSlot(mcia_results_sc, "global_scores")) {
          write.csv(as.data.frame(mcia_results_sc@global_scores), "global_scores.csv", row.names = TRUE)
        }
        if (.hasSlot(mcia_results_sc, "global_loadings")) {
          write.csv(as.data.frame(mcia_results_sc@global_loadings), "global_loadings.csv", row.names = TRUE)
        }
        
        # 5. Visualize eigenvalues, global scores, heatmaps, and loadings
        meta_colors_sc <- get_metadata_colors(
          mcia_results = mcia_results_sc,
          color_col = "CellType",
          color_pal = scales::viridis_pal,
          color_pal_params = list(option = "D")
        )
        
        colors_omics_sc <- get_colors(mcia_results = mcia_results_sc)
        
        # Save plots to PDF files
        pdf("global_scores_eigenvalues_plot.pdf", width = 7, height = 5)
        print(global_scores_eigenvalues_plot(mcia_results = mcia_results_sc))
        dev.off()
        
        pdf("projection_plot.pdf", width = 7, height = 6)
        print(projection_plot(
          mcia_results = mcia_results_sc,
          projection = "global",
          orders = c(1, 2),
          color_col = "CellType",
          color_pal = meta_colors_sc,
          legend_loc = "bottomright"
        ))
        dev.off()
        
        pdf("global_scores_heatmap.pdf", width = 8, height = 8)
        print(global_scores_heatmap(
          mcia_results = mcia_results_sc,
          color_col = "CellType",
          color_pal = meta_colors_sc
        ))
        dev.off()
        
        pdf("block_weights_heatmap.pdf", width = 6, height = 5)
        print(block_weights_heatmap(mcia_results = mcia_results_sc))
        dev.off()
        
        pdf("vis_load_plot.pdf", width = 7, height = 6)
        print(vis_load_plot(
          mcia_results = mcia_results_sc,
          axes = c(1, 4),
          color_pal = colors_omics_sc
        ))
        dev.off()

    writeLines(c(
        '"BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA":',
        paste0('    nipalsMCIA: ', as.character(packageVersion('nipalsMCIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_cite_seq_mcia.csv versions.yml
    """
}

workflow BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ obj, metadata_sc ] ]

    main:
    BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA(ch_input)

    emit:
    tables   = BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA.out.tables
    plots    = BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA.out.plots
    objects  = BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA.out.objects
    versions = BIOC_NIPALSMCIA_SINGLE_CELL_CITE_SEQ_MCIA.out.versions
}
