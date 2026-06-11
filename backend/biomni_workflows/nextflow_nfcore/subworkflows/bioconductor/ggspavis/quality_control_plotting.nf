#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggspavis — quality_control_plotting
// Generate spot-level and feature-level quality control plots to identify low-quality spots or lowly abundant features.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-ggspavis:1.16.0--r45hdfd78af_0
// R packages: SpatialExperiment, ggplot2, ggspavis, patchwork
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, ggplot2, ggspavis, patchwork
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot spot-level QC metrics using histograms, violins, and spatial spot plots via plotObsQC
//  * 2. [Visualization & Output] Plot bivariate QC relationships using scatter plots with thresholds via plotObsQC
//  * 3. [Visualization & Output] Plot feature-level QC metrics using histograms and violins via plotFeatureQC

nextflow.enable.dsl = 2

process BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING {
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
    .bm_deps <- c("SpatialExperiment", "ggplot2", "ggspavis", "patchwork")
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
    library(ggspavis)
    library(SpatialExperiment)
    library(patchwork)
    library(ggplot2)
    
    # -----------------------------------------------------------------------------
    # 1. Load Input Data
    # -----------------------------------------------------------------------------
    # The pipeline reads the SpatialExperiment object 'spe' from the working directory.
    # We check for both 'spe' and 'spe.rds' to be robust.
    if (file.exists("spe")) {
      spe <- readRDS("spe")
    } else if (file.exists("spe.rds")) {
      spe <- readRDS("spe.rds")
    } else {
      stop("Error: Input file 'spe' or 'spe.rds' not found in the working directory.")
    }
    
    # Ensure the loaded object is a SpatialExperiment
    if (!inherits(spe, "SpatialExperiment")) {
      stop("Error: Loaded object is not of class 'SpatialExperiment'.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Spot-level QC: Low Library Size
    # -----------------------------------------------------------------------------
    p1_lib <- plotObsQC(spe, plot_type = "histogram", 
                        x_metric = "sum", annotate = "low_libsize")
    p2_lib <- plotObsQC(spe, plot_type = "violin", 
                        x_metric = "sum", annotate = "low_libsize", point_size = 0.1)
    p3_lib <- plotObsQC(spe, plot_type = "spot", in_tissue = "in_tissue", 
                        annotate = "low_libsize", point_size = 0.2)
    
    # Combine plots using patchwork
    combined_libsize <- p1_lib | p2_lib | p3_lib
    
    # Save the combined plot
    ggsave("qc_spot_low_libsize.pdf", plot = combined_libsize, width = 12, height = 4)
    
    # -----------------------------------------------------------------------------
    # 3. Spot-level QC: High Mitochondrial Proportion
    # -----------------------------------------------------------------------------
    p1_mito <- plotObsQC(spe, plot_type = "histogram", 
                         x_metric = "subsets_mito_percent", annotate = "high_mito")
    p2_mito <- plotObsQC(spe, plot_type = "violin", 
                         x_metric = "subsets_mito_percent", annotate = "high_mito", 
                         point_size = 0.1)
    p3_mito <- plotObsQC(spe, plot_type = "spot", in_tissue = "in_tissue", 
                         annotate = "high_mito", point_size = 0.2)
    
    # Combine plots using patchwork
    combined_mito <- p1_mito | p2_mito | p3_mito
    
    # Save the combined plot
    ggsave("qc_spot_high_mito.pdf", plot = combined_mito, width = 12, height = 4)
    
    # -----------------------------------------------------------------------------
    # 4. Bivariate QC Relationships (Scatter Plot)
    # -----------------------------------------------------------------------------
    scatter_plot <- plotObsQC(spe, plot_type = "scatter", 
                              x_metric = "subsets_mito_percent", y_metric = "sum", 
                              x_threshold = 30, y_threshold = 400)
    
    # Save the scatter plot
    ggsave("qc_bivariate_scatter.pdf", plot = scatter_plot, width = 6, height = 5)
    
    # -----------------------------------------------------------------------------
    # 5. Feature-level QC
    # -----------------------------------------------------------------------------
    p1_feat <- plotFeatureQC(spe, plot_type = "histogram", 
                             x_metric = "feature_sum", annotate = "low_abundance")
    p2_feat <- plotFeatureQC(spe, plot_type = "violin", 
                             x_metric = "feature_sum", annotate = "low_abundance")
    
    # Combine plots using patchwork
    combined_feat <- p1_feat | p2_feat
    
    # Save the combined plot
    ggsave("qc_feature_abundance.pdf", plot = combined_feat, width = 8, height = 4)

    writeLines(c(
        '"BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING":',
        paste0('    ggspavis: ', as.character(packageVersion('ggspavis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quality_control_plotting.csv versions.yml
    """
}

workflow BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING.out.tables
    plots    = BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING.out.plots
    objects  = BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING.out.objects
    versions = BIOC_GGSPAVIS_QUALITY_CONTROL_PLOTTING.out.versions
}
