#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: glmGamPoi — cell_level_marker_gene_identification
// Fit a Gamma-Poisson GLM directly on cell-level single-cell data to identify marker genes between cell types.
// Input: sce_subset
// Container: quay.io/biocontainers/bioconductor-glmgampoi:1.22.0--r45ha27e39d_0
// R packages: SingleCellExperiment, ggplot2, glmGamPoi
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, glmGamPoi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the Gamma-Poisson GLM on cell-level data using glm_gp()
//  * 2. [Core Analysis] Identify marker genes in the control condition using test_de()
//  * 3. [Core Analysis] Identify marker genes in the stimulated condition using test_de() with combined coefficients

nextflow.enable.dsl = 2

process BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION {
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
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "glmGamPoi")
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
        library(glmGamPoi)
        library(ggplot2)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input
        # -----------------------------------------------------------------------------
        # The pipeline reads the 'sce_subset' SingleCellExperiment object from the working directory.
        if (file.exists("sce_subset")) {
          sce_subset <- readRDS("sce_subset")
        } else if (file.exists("sce_subset.rds")) {
          sce_subset <- readRDS("sce_subset.rds")
        } else {
          stop("Error: Input file 'sce_subset' or 'sce_subset.rds' not found in the working directory.")
        }
        
        # Ensure there are no empty factor levels in the design variables to prevent glm_gp() failure
        # Also ensure they are factors so levels() can be extracted dynamically
        if (!is.null(sce_subset\$cell)) {
          sce_subset\$cell <- droplevels(as.factor(sce_subset\$cell))
        }
        if (!is.null(sce_subset\$stim)) {
          sce_subset\$stim <- droplevels(as.factor(sce_subset\$stim))
        }
        
        # Dynamically extract available levels for contrasts
        cell_levels <- levels(sce_subset\$cell)
        stim_levels <- levels(sce_subset\$stim)
        
        cell_A <- cell_levels[1]
        cell_B <- cell_levels[2]
        stim_ctrl <- stim_levels[1]
        stim_stim <- stim_levels[2]
        
        # -----------------------------------------------------------------------------
        # Stage 1: Fit the Gamma-Poisson GLM on cell-level data
        # -----------------------------------------------------------------------------
        fit <- glm_gp(sce_subset, design = ~ cell + stim +  stim:cell - 1)
        
        # Save the fitted model object
        saveRDS(fit, file = "glm_gp_fit.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Identify marker genes in the control condition
        # -----------------------------------------------------------------------------
        marker_genes <- test_de(fit, contrast = cond(cell = cell_A, stim = stim_ctrl) - cond(cell = cell_B, stim = stim_ctrl), sort_by = pval)
        
        # Save control condition marker genes to CSV
        write.csv(as.data.frame(marker_genes), file = "marker_genes_control.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Identify marker genes in the stimulated condition
        # -----------------------------------------------------------------------------
        marker_genes2 <- test_de(fit, contrast = cond(cell = cell_A, stim = stim_stim) - cond(cell = cell_B, stim = stim_stim), sort_by = pval)
        
        # Save stimulated condition marker genes to CSV
        write.csv(as.data.frame(marker_genes2), file = "marker_genes_stimulated.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Generate and save visualization
        # -----------------------------------------------------------------------------
        # Create a visualization of the top marker genes from the control condition
        tryCatch({
          top_genes <- marker_genes\$name[1:6]
          
          # Extract expression values for the top genes
          counts_matrix <- assay(sce_subset, "counts")
          expression_data <- as.matrix(counts_matrix[top_genes, , drop = FALSE])
          
          # Construct data frame for plotting
          plot_df <- data.frame(
            gene = rep(top_genes, times = ncol(sce_subset)),
            expression = as.vector(expression_data),
            celltype = rep(sce_subset\$cell, each = length(top_genes))
          )
          
          # Generate plot
          p <- ggplot(plot_df, aes(x = celltype, y = expression)) +
            geom_jitter(height = 0.1, width = 0.2, alpha = 0.5, size = 0.5) +
            stat_summary(geom = "crossbar", fun = "mean", color = "red", width = 0.5) +
            facet_wrap(~ gene, scales = "free_y") +
            theme_bw() +
            labs(
              title = paste0("Marker genes of ", cell_A, " vs. ", cell_B, " (Control Condition)"),
              x = "Cell Type",
              y = "Expression Count"
            ) +
            theme(axis.text.x = element_text(angle = 45, hjust = 1))
          
          # Save plot to PDF
          ggsave("marker_genes_expression_plot.pdf", plot = p, width = 8, height = 6)
        }, error = function(e) {
          warning("Visualization step skipped or failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION":',
        paste0('    glmGamPoi: ', as.character(packageVersion('glmGamPoi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_level_marker_gene_identification.csv versions.yml
    """
}

workflow BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_subset ] ]

    main:
    BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION(ch_input)

    emit:
    tables   = BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION.out.tables
    plots    = BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION.out.plots
    objects  = BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION.out.objects
    versions = BIOC_GLMGAMPOI_CELL_LEVEL_MARKER_GENE_IDENTIFICATION.out.versions
}
