#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tricycle — custom_reference_projection
// Build a custom cell cycle reference using PCA on Gene Ontology cell cycle genes and project data using this new reference.
// Input: sce_normalized.rds
// Container: quay.io/biocontainers/bioconductor-tricycle:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CircStats, SingleCellExperiment, ggplot2, tricycle
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run PCA on Gene Ontology cell cycle genes using run_pca_cc_genes()
//  * 2. [Core Analysis] Extract the rotation matrix for the top 2 PCs to serve as the new reference
//  * 3. [Core Analysis] Estimate cell cycle position using the custom reference matrix with estimate_cycle_position()
//  * 4. [Core Analysis] Compare the new positions with original positions using circular correlation

nextflow.enable.dsl = 2

process BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION {
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
    .bm_deps <- c("tricycle", "ggplot2", "CircStats")
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
    library(tricycle)
    library(ggplot2)
    library(CircStats)
    
    # 1. Read user input
    sce <- readRDS("sce_normalized.rds")
    
    # 2. Estimate original cycle position using default reference
    # This is required to populate sce\$tricyclePosition for comparison
    sce <- estimate_cycle_position(sce)
    
    # 3. Run PCA on Gene Ontology cell cycle genes
    set.seed(100)
    gocc_sce.o <- run_pca_cc_genes(sce,
                                   exprs_values = "logcounts", species = "mouse")
    
    # 4. Extract the rotation matrix for the top 2 PCs to serve as the new reference
    new.ref <- attr(reducedDim(gocc_sce.o, 'PCA'), 'rotation')[, seq_len(2)]
    head(new.ref)
    
    # Save the custom reference matrix
    write.csv(as.data.frame(new.ref), "custom_reference_rotation.csv", row.names = TRUE)
    
    # 5. Estimate cell cycle position using the custom reference matrix
    new_sce <- estimate_cycle_position(sce, ref.m  = new.ref,
                                       dimred = 'tricycleEmbedding2')
    
    # Save the updated SingleCellExperiment object
    saveRDS(new_sce, "sce_with_custom_positions.rds")
    
    # 6. Compare the new positions with original positions
    linear_cor <- cor(sce\$tricyclePosition, new_sce\$tricyclePosition)
    circular_cor <- CircStats::circ.cor(sce\$tricyclePosition, new_sce\$tricyclePosition)
    
    # Save correlation results
    cor_results <- data.frame(
      Metric = c("Pearson Correlation", "Circular Correlation"),
      Value = c(linear_cor, circular_cor)
    )
    write.csv(cor_results, "position_correlation_results.csv", row.names = FALSE)
    
    # 7. Generate and save comparison plot
    p <- qplot(x = sce\$tricyclePosition, y = new_sce\$tricyclePosition) +
      labs(x = "Original \u03b8", y = "New \u03b8",
           title = paste0("Comparison of two \u03b8 (n=", ncol(sce), ")")) +
      theme_bw(base_size = 14)
    
    ggsave("theta_comparison_plot.pdf", plot = p, width = 7, height = 6)

    writeLines(c(
        '"BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION":',
        paste0('    tricycle: ', as.character(packageVersion('tricycle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_reference_projection.csv versions.yml
    """
}

workflow BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_normalized.rds ] ]

    main:
    BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION(ch_input)

    emit:
    tables   = BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION.out.tables
    plots    = BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION.out.plots
    objects  = BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION.out.objects
    versions = BIOC_TRICYCLE_CUSTOM_REFERENCE_PROJECTION.out.versions
}
