#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: imcRtools — interaction_permutation_testing
// Count and test the significance of cell-cell interactions across images using permutation testing, and visualize interaction networks.
// Input: SingleCellExperiment.rds
// Container: quay.io/biocontainers/bioconductor-imcrtools:1.16.0--r45hdfd78af_0
// R packages: BiocParallel, RColorBrewer, SingleCellExperiment, SpatialExperiment, data.table, ggplot2, ggraph, imcRtools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: network plot, dot plot

nextflow.enable.dsl = 2

process BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-imcrtools:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocParallel", "RColorBrewer", "SingleCellExperiment", "SpatialExperiment", "data.table", "ggplot2", "ggraph", "imcRtools", "SummarizedExperiment")
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
    library(imcRtools)
    library(SummarizedExperiment)
    library(SingleCellExperiment)
    library(SpatialExperiment)
    library(data.table)
    library(ggplot2)
    library(ggraph)
    library(BiocParallel)
    library(RColorBrewer)
    
    # --- Load the user-provided ---
    if (!file.exists("SingleCellExperiment.rds")) {
      stop("Error: 'SingleCellExperiment.rds' not found in the working directory.")
    }
    
    pancreasSCE <- readRDS("SingleCellExperiment.rds")
    
    # --- Count interactions using countInteractions (classic ---
    out_classic_count <- countInteractions(
      pancreasSCE, 
      group_by = "ImageNb", 
      label = "CellType", 
      method = "classic", 
      colPairName = "knn_interaction_graph"
    )
    
    # Save classic interaction counts
    write.csv(as.data.frame(out_classic_count), "classic_interaction_counts.csv", row.names = FALSE)
    
    # --- Test interactions via permutation using testInteractions ---
    out <- testInteractions(
      pancreasSCE, 
      group_by = "ImageNb", 
      label = "CellType", 
      method = "classic", 
      colPairName = "knn_interaction_graph", 
      BPPARAM = BiocParallel::SerialParam(RNGseed = 123)
    )
    
    # Save classic interaction test results
    write.csv(as.data.frame(out), "classic_interaction_tests.csv", row.names = FALSE)
    
    # --- Visualize interaction networks using plotInteractions ---
    pdf("classic_interactions_network.pdf", width = 8, height = 6)
    p1 <- plotInteractions(out, pancreasSCE, group_by = "ImageNb", label = "CellType")
    print(p1)
    dev.off()
    
    # --- Perform conditional cell ratio (CCR) analysis for ---
    out <- testInteractions(
      pancreasSCE, 
      group_by = "ImageNb", 
      label = "CellType", 
      method = "conditional", 
      colPairName = "knn_interaction_graph", 
      BPPARAM = BiocParallel::SerialParam(RNGseed = 123)
    )
    
    cd <- as.data.table(colData(pancreasSCE))
    
    cond_ratio_df <- as.data.table(colPair(pancreasSCE, "knn_interaction_graph"))[
      , .(from_label = cd\$CellType[from], to_label = cd\$CellType[to], group_by = cd\$ImageNb[from], from)
    ][
      , .(N = uniqueN(from)), by = .(group_by, from_label, to_label)
    ][
      cd[, .(total_from_type = .N), by = .(group_by = ImageNb, from_label = CellType)], 
      on = .(group_by, from_label)
    ][
      , .(group_by, from_label, to_label, cond_ratio = N / total_from_type)
    ]
    
    out_cr <- merge(
      as.data.table(out)[, `:=`(
        group_by = as.integer(group_by), 
        from_label = as.character(from_label), 
        to_label = as.character(to_label)
      )], 
      cond_ratio_df, 
      by = c("group_by", "from_label", "to_label"), 
      all.x = TRUE
    )
    
    # Save conditional interaction results with CCR
    write.csv(out_cr, "conditional_interactions_with_ccr.csv", row.names = FALSE)
    
    # --- Visualize conditional results (z-score and CCR) ---
    p_data <- out_cr[!is.na(zscore) & !is.na(cond_ratio) & sig == TRUE]
    if (nrow(p_data) > 0) {
      pdf("conditional_interactions_dotplot.pdf", width = 10, height = 8)
      p2 <- ggplot(p_data, aes(from_label, to_label, size = cond_ratio, color = zscore)) +
        geom_point() +
        theme_bw() +
        scale_size(range = c(1, 10)) +
        scale_color_gradient2(
          low = brewer.pal(11, "RdBu")[10], 
          mid = "white", 
          high = brewer.pal(11, "RdBu")[2], 
          midpoint = 0
        ) +
        facet_wrap(~group_by)
      print(p2)
      dev.off()
    } else {
      message("No significant conditional interactions found to plot.")
    }

    writeLines(c(
        '"BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING":',
        paste0('        imcRtools: ', as.character(packageVersion("imcRtools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interaction_permutation_testing.csv versions.yml
    """
}

workflow BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SingleCellExperiment.rds ] ]

    main:
    BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING(ch_input)

    emit:
    tables   = BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING.out.tables
    plots    = BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING.out.plots
    objects  = BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING.out.objects
    versions = BIOC_IMCRTOOLS_INTERACTION_PERMUTATION_TESTING.out.versions
}
