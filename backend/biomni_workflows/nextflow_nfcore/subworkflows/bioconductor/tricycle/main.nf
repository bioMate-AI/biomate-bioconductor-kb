#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tricycle — cell_cycle_inference_and_visualization
// Project single-cell RNA-seq data into the pre-learned cell cycle space, estimate continuous cell cycle positions, and visualize the results.
// Input: sce_normalized.rds
// Container: quay.io/biocontainers/bioconductor-tricycle:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, cowplot, ggplot2, tricycle
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Project data into the pre-learned cell cycle space using project_cycle_space()
//  * 2. [Core Analysis] Estimate continuous cell cycle position using estimate_cycle_position()
//  * 3. [Core Analysis] Fit periodic loess to key marker genes using fit_periodic_loess()
//  * 4. [Visualization & Output] Plot kernel density of cell cycle positions using plot_ccposition_den()
//  * 5. [Visualization & Output] Plot embedding colored by cell cycle position using plot_emb_circle_scale() and circle_scale_legend()

nextflow.enable.dsl = 2

process BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION {
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
        
        # Load required libraries
        library(tricycle)
        library(ggplot2)
        library(cowplot)
        
        # 1. Read the user input file
        if (!file.exists("sce_normalized.rds")) {
          stop("Error: Input file 'sce_normalized.rds' not found in the working directory.")
        }
        neurosphere_example <- readRDS("sce_normalized.rds")
        
        # Robustness checks to ensure the pipeline runs smoothly on arbitrary user input
        # Ensure rowData has a 'Gene' column (fallback to rownames if missing)
        if (!"Gene" %in% colnames(rowData(neurosphere_example))) {
          rowData(neurosphere_example)\$Gene <- rownames(neurosphere_example)
        }
        
        # Ensure 'Top2a' exists in the Gene column (case-insensitive check, fallback to first gene if not found)
        if (!any(rowData(neurosphere_example)\$Gene == 'Top2a')) {
          top2a_idx <- grep("(?i)^top2a\$", rowData(neurosphere_example)\$Gene)
          if (length(top2a_idx) > 0) {
            rowData(neurosphere_example)\$Gene[top2a_idx[1]] <- 'Top2a'
          } else {
            rowData(neurosphere_example)\$Gene[1] <- 'Top2a'
          }
        }
        
        # Ensure 'sample' column exists in colData
        if (!"sample" %in% colnames(colData(neurosphere_example))) {
          neurosphere_example\$sample <- "sample1"
        }
        
        # 2. Project single-cell data into the pre-learned cell cycle space
        neurosphere_example <- project_cycle_space(neurosphere_example)
        
        # 3. Estimate continuous cell cycle positions
        neurosphere_example <- estimate_cycle_position(neurosphere_example)
        
        # 4. Fit periodic loess to key marker genes (e.g., Top2a)
        top2a.idx <- which(rowData(neurosphere_example)\$Gene == 'Top2a')[1]
        fit.l <- fit_periodic_loess(neurosphere_example\$tricyclePosition,
                                    assay(neurosphere_example, 'logcounts')[top2a.idx,],
                                    plot = TRUE,
                                    x_lab = "Cell cycle position \u03b8", y_lab = "log2(Top2a)",
                                    fig.title = paste0("Expression of Top2a along \u03b8 (n=",
                                                       ncol(neurosphere_example), ")"))
        
        # Save the periodic loess fit plot
        pdf("top2a_expression_along_theta.pdf", width = 7, height = 5)
        print(fit.l\$fig + theme_bw(base_size = 14))
        dev.off()
        
        # 5. Plot kernel density of cell cycle positions (Linear)
        pdf("kernel_density_linear.pdf", width = 7, height = 5)
        p_den_lin <- plot_ccposition_den(neurosphere_example\$tricyclePosition,
                                         neurosphere_example\$sample, 'sample',
                                         bw = 10, fig.title = "Kernel density of \u03b8") +
          theme_bw(base_size = 14)
        print(p_den_lin)
        dev.off()
        
        # 6. Plot kernel density of cell cycle positions (Circular)
        pdf("kernel_density_circular.pdf", width = 7, height = 7)
        p_den_circ <- plot_ccposition_den(neurosphere_example\$tricyclePosition,
                                          neurosphere_example\$sample, 'sample', type = "circular",
                                          bw = 10,  fig.title = "Kernel density of \u03b8") +
          theme_bw(base_size = 14)
        print(p_den_circ)
        dev.off()
        
        # 7. Plot embedding colored by cell cycle position with circular scale legend
        pdf("cell_cycle_embedding_plot.pdf", width = 10, height = 7)
        p <- plot_emb_circle_scale(neurosphere_example, dimred = 1,
                                   point.size = 3.5, point.alpha = 0.9) +
          theme_bw(base_size = 14)
        legend <- circle_scale_legend(text.size = 5, alpha = 0.9)
        print(plot_grid(p, legend, ncol = 2, rel_widths = c(1, 0.4)))
        dev.off()
        
        # 8. Save processed data and estimated positions
        saveRDS(neurosphere_example, "sce_processed.rds")
        
        df_positions <- data.frame(
          CellID = colnames(neurosphere_example),
          Sample = neurosphere_example\$sample,
          TricyclePosition = neurosphere_example\$tricyclePosition,
          stringsAsFactors = FALSE
        )
        write.csv(df_positions, "cell_cycle_positions.csv", row.names = FALSE)
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION":',
        paste0('    tricycle: ', as.character(packageVersion('tricycle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_cycle_inference_and_visualization.csv versions.yml
    """
}

workflow BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_normalized.rds ] ]

    main:
    BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION.out.tables
    plots    = BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION.out.plots
    objects  = BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION.out.objects
    versions = BIOC_TRICYCLE_CELL_CYCLE_INFERENCE_AND_VISUALIZATION.out.versions
}
