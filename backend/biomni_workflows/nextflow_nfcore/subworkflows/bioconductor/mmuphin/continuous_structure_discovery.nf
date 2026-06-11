#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MMUPHin — continuous_structure_discovery
// Identify and validate continuous population gradients (consensus loadings and scores) across multiple microbiome studies.
// Input: adjusted_abundance_table.tsv, metadata.tsv
// Container: quay.io/biocontainers/bioconductor-mmuphin:1.16.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MMUPHin, dplyr, ggplot2, magrittr, vegan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run continuous_discover to extract consensus loadings and scores across cohorts

nextflow.enable.dsl = 2

process BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("MMUPHin", "magrittr", "dplyr", "ggplot2", "vegan")
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
    library(MMUPHin)
    library(magrittr)
    library(dplyr)
    library(ggplot2)
    library(vegan)
    
    # Read user input files from the working directory
    # adjusted_abundance_table.tsv: batch-adjusted feature-by-sample abundance matrix
    # metadata.tsv: sample metadata containing batch and subsetting variables
    control_abd_adj <- as.matrix(read.table("adjusted_abundance_table.tsv",
                                            header = TRUE,
                                            sep = "\t",
                                            row.names = 1,
                                            check.names = FALSE))
    
    control_meta <- read.table("metadata.tsv",
                               header = TRUE,
                               sep = "\t",
                               row.names = 1,
                               check.names = FALSE)
    
    # Align samples between abundance matrix and metadata
    common_samples <- intersect(colnames(control_abd_adj), rownames(control_meta))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between adjusted_abundance_table.tsv and metadata.tsv")
    }
    control_abd_adj <- control_abd_adj[, common_samples, drop = FALSE]
    control_meta <- control_meta[common_samples, , drop = FALSE]
    
    # Run continuous_discover to extract consensus loadings and scores across cohorts
    # This call reproduces the documented code exactly as specified.
    fit_continuous <- continuous_discover(feature_abd = control_abd_adj,
                                          batch = "studyID",
                                          data = control_meta,
                                          control = list(var_perc_cutoff = 0.5,
                                                         verbose = FALSE))
    
    # Save the RDS object of the fit
    saveRDS(fit_continuous, "fit_continuous.rds")
    
    # Extract and save consensus loadings
    loading <- data.frame(feature = rownames(fit_continuous\$consensus_loadings),
                          loading1 = fit_continuous\$consensus_loadings[, 1])
    write.csv(loading, "consensus_loadings.csv", row.names = FALSE)
    
    # Extract and save consensus scores
    scores <- data.frame(sample = rownames(fit_continuous\$consensus_scores),
                         score1 = fit_continuous\$consensus_scores[, 1])
    write.csv(scores, "consensus_scores.csv", row.names = FALSE)
    
    # Generate and save diagnostic plots
    pdf("continuous_structure_discovery_plots.pdf", width = 12, height = 6)
    
    # Plot 1: Top contributing features
    p1 <- loading %>%
      arrange(-abs(loading1)) %>%
      slice(1:20) %>%
      arrange(loading1) %>%
      mutate(feature = factor(feature, levels = feature)) %>%
      ggplot(aes(x = feature, y = loading1)) +
      geom_bar(stat = "identity") +
      coord_flip() +
      ggtitle("Features with top loadings") +
      theme_minimal()
    print(p1)
    
    # Plot 2: Ordination overlay with continuous scores
    tryCatch({
      D_control <- vegdist(t(control_abd_adj))
      mds <- cmdscale(d = D_control)
      colnames(mds) <- c("Axis1", "Axis2")
      p2 <- as.data.frame(mds) %>%
        mutate(score1 = fit_continuous\$consensus_scores[, 1]) %>%
        ggplot(aes(x = Axis1, y = Axis2, color = score1)) +
        geom_point(size = 3, alpha = 0.8) +
        scale_color_viridis_c() +
        coord_fixed() +
        ggtitle("MDS Ordination colored by Consensus Score 1") +
        theme_minimal()
      print(p2)
    }, error = function(e) {
      warning("Could not generate MDS plot: ", e\$message)
    })
    
    dev.off()
    
    cat("Workflow completed successfully. Outputs saved to 'fit_continuous.rds', 'consensus_loadings.csv', 'consensus_scores.csv', and 'continuous_structure_discovery_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY":',
        paste0('    MMUPHin: ', as.character(packageVersion('MMUPHin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_continuous_structure_discovery.csv versions.yml
    """
}

workflow BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ adjusted_abundance_table.tsv, metadata.tsv ] ]

    main:
    BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY.out.tables
    plots    = BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY.out.plots
    objects  = BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY.out.objects
    versions = BIOC_MMUPHIN_CONTINUOUS_STRUCTURE_DISCOVERY.out.versions
}
