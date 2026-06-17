#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nipalsMCIA — multiblock_mcia_decomposition
// Perform MCIA on multi-block data (e.g., mRNA, miRNA, protein), visualize global scores, block weights, and feature loadings.
// Input: data_blocks, metadata_NCI60
// Container: quay.io/biocontainers/bioconductor-nipalsmcia:1.8.1--r45hdfd78af_0
// R packages: BiocFileCache, ComplexHeatmap, dplyr, ggplot2, ggpubr, MultiAssayExperiment, nipalsMCIA, Seurat
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, dplyr, ggplot2, ggpubr, nipalsMCIA
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert data list to a MultiAssayExperiment (MAE) using simple_mae()
//  * 2. [Core Analysis] Run MCIA decomposition using nipals_multiblock()
//  * 3. [Visualization & Output] Visualize global scores using projection_plot()
//  * 4. [Visualization & Output] Visualize sample clustering using global_scores_heatmap()
//  * 5. [Visualization & Output] Visualize block contributions using block_weights_heatmap()
//  * 6. [Visualization & Output] Visualize feature loadings using vis_load_plot(), vis_load_ord(), and ord_loadings()

nextflow.enable.dsl = 2

process BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION {
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
    .bm_deps <- c("BiocFileCache", "ComplexHeatmap", "dplyr", "ggplot2", "ggpubr", "MultiAssayExperiment", "nipalsMCIA", "Seurat")
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
        library(nipalsMCIA)
        library(ggpubr)
        library(ggplot2)
        library(ComplexHeatmap)
        library(dplyr)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input Files
        # -----------------------------------------------------------------------------
        if (!file.exists("data_blocks.rds") || !file.exists("metadata_NCI60.rds")) {
          stop("Required input files 'data_blocks.rds' and 'metadata_NCI60.rds' must exist in the working directory.")
        }
        
        data_blocks <- readRDS("data_blocks.rds")
        metadata_NCI60 <- readRDS("metadata_NCI60.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 1: Convert data list to a MultiAssayExperiment (MAE) using simple_mae()
        # -----------------------------------------------------------------------------
        data_blocks_mae <- simple_mae(data_blocks, row_format = "sample")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Run MCIA decomposition using nipals_multiblock() (No Metadata)
        # -----------------------------------------------------------------------------
        set.seed(42)
        mcia_results <- nipals_multiblock(data_blocks_mae, col_preproc_method = "colprofile", num_PCs = 10, tol = 1e-12, plots = "none")
        
        # Print slot names to console
        print(slotNames(mcia_results))
        
        # -----------------------------------------------------------------------------
        # Stage 3: Visualize global scores using projection_plot() (No Metadata)
        # -----------------------------------------------------------------------------
        pdf("projection_plot_no_metadata.pdf", width = 7, height = 7)
        print(projection_plot(mcia_results, projection = "global", orders = c(1, 2)))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 4: Re-run MCIA with Metadata
        # -----------------------------------------------------------------------------
        data_blocks_mae <- simple_mae(data_blocks, row_format = "sample", colData = metadata_NCI60)
        
        set.seed(42)
        mcia_results <- nipals_multiblock(data_blocks_mae, col_preproc_method = "colprofile", plots = "none", num_PCs = 10, tol = 1e-12)
        
        # Save the final decomposition results object
        saveRDS(mcia_results, "mcia_results.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 5: Visualize global scores using projection_plot() (With Metadata)
        # -----------------------------------------------------------------------------
        meta_colors <- get_metadata_colors(mcia_results, color_col = 1, color_pal_params = list(option = "E"))
        
        pdf("projection_plot_with_metadata.pdf", width = 8, height = 7)
        print(projection_plot(mcia_results, projection = "global", orders = c(1, 2), color_col = "cancerType", color_pal = meta_colors, legend_loc = "bottomleft"))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 6: Visualize sample clustering using global_scores_heatmap()
        # -----------------------------------------------------------------------------
        pdf("global_scores_heatmap.pdf", width = 8, height = 8)
        print(global_scores_heatmap(mcia_results = mcia_results, color_col = "cancerType", color_pal = meta_colors))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 7: Visualize block contributions using block_weights_heatmap()
        # -----------------------------------------------------------------------------
        pdf("block_weights_heatmap.pdf", width = 7, height = 5)
        print(block_weights_heatmap(mcia_results))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 8: Visualize feature loadings using vis_load_plot(), vis_load_ord()
        # -----------------------------------------------------------------------------
        colors_omics <- get_colors(mcia_results)
        
        pdf("vis_load_plot.pdf", width = 8, height = 7)
        print(vis_load_plot(mcia_results, axes = c(1, 4), color_pal = colors_omics))
        dev.off()
        
        all_pos_1_vis <- vis_load_ord(mcia_results, omic = "all", factor = 1, absolute = FALSE, descending = TRUE)
        mrna_pos_1_vis <- vis_load_ord(mcia_results, omic = "mrna", factor = 1, absolute = FALSE, descending = TRUE)
        
        pdf("loadings_scree_plots.pdf", width = 12, height = 6)
        print(ggpubr::ggarrange(all_pos_1_vis, mrna_pos_1_vis))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 9: Extract and save ordered loadings tables using ord_loadings()
        # -----------------------------------------------------------------------------
        all_pos_1 <- ord_loadings(mcia_results, omic = "all", factor = 1, absolute = FALSE, descending = TRUE)
        mrna_pos_1 <- ord_loadings(mcia_results, omic = "mrna", factor = 1, absolute = FALSE, descending = TRUE)
        
        write.csv(all_pos_1, "all_pos_1_loadings.csv", row.names = TRUE)
        write.csv(mrna_pos_1, "mrna_pos_1_loadings.csv", row.names = TRUE)
        
        message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION":',
        paste0('    nipalsMCIA: ', as.character(packageVersion('nipalsMCIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiblock_mcia_decomposition.csv versions.yml
    """
}

workflow BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_blocks, metadata_NCI60 ] ]

    main:
    BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION(ch_input)

    emit:
    tables   = BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION.out.tables
    plots    = BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION.out.plots
    objects  = BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION.out.objects
    versions = BIOC_NIPALSMCIA_MULTIBLOCK_MCIA_DECOMPOSITION.out.versions
}
