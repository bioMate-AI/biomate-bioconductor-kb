#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggmanh — binned_manhattan_plot
// Create a binned grid-based Manhattan plot for extremely large datasets to avoid plotting individual points, with custom bin summaries.
// Input: large_gwas_results.csv
// Container: quay.io/biocontainers/bioconductor-ggmanh:1.14.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Polychrome, ggmanh, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Preprocess binned data using binned_manhattan_preprocess() with custom summary expressions
//  * 2. [Visualization & Output] Plot the binned data using binned_manhattan_plot()

nextflow.enable.dsl = 2

process BIOC_GGMANH_BINNED_MANHATTAN_PLOT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ggmanh", "ggplot2")
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
    library(ggmanh)
    library(ggplot2)
    
    # Read the user-provided large-scale GWAS summary statistics
    simdata <- read.csv("large_gwas_results.csv")
    
    # Ensure chromosome is a factor to avoid ambiguity in plotting
    simdata\$chromosome <- factor(simdata\$chromosome)
    
    # 1. Basic Binned Manhattan Plot
    pdf("binned_manhattan_plot_basic.pdf", width = 10, height = 6)
    p1 <- binned_manhattan_plot(
      simdata, 
      pval.colname = "P.value", 
      chr.colname = "chromosome", 
      pos.colname = "position"
    )
    print(p1)
    dev.off()
    
    # 2. Binned Manhattan Plot with custom bins and title
    pdf("binned_manhattan_plot_custom_bins.pdf", width = 10, height = 6)
    p2 <- binned_manhattan_plot(
      simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", 
      bins.x = 7, # number of bins for the "widest" chromosome, either calculated by position or by number of variants
      bins.y = 100, # number of vertical bins
      show.legend = FALSE, plot.title = "Binned Manhattan Plot"
    )
    print(p2)
    dev.off()
    
    # 3. Preprocess binned data and plot with bin outlines
    mpdat <- binned_manhattan_preprocess(
      simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position",
      bins.x = 7, bins.y = 100,
      chr.gap.scaling = 0.5, # scaling factor for chromosome gap
      show.message = FALSE # this suppresses some warning messages built into the function
    )
    
    pdf("binned_manhattan_plot_outlined.pdf", width = 10, height = 6)
    p3 <- binned_manhattan_plot(mpdat, bin.outline = TRUE)
    print(p3)
    dev.off()
    
    # 4. Preprocess binned data with custom summary expressions
    mpdata <- binned_manhattan_preprocess(
      simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position",
      bins.x = 7, bins.y = 100, chr.gap.scaling = 0.5,
      # summary expression list
      summarise.expression.list = list(
        max_log10p ~ max(-log10(P.value)), # creates column "max_log10p", which holds the maximum -log10(P.value) among the variants inside the bin
        signif ~ ifelse(max(P.value) < 5e-8, "Significant", "Not Significant") # creates column "signif" which indicates significance of the bin
      )
    )
    
    # Save the preprocessed binned data object and summary table
    saveRDS(mpdata, "mpdata_binned_summary.rds")
    write.csv(as.data.frame(mpdata\$data), "mpdata_binned_summary_table.csv", row.names = FALSE)
    
    # 5. Plot the preprocessed binned data with custom palette and highlights
    pdf("binned_manhattan_plot_custom_summary.pdf", width = 10, height = 6)
    p4 <- binned_manhattan_plot(
      mpdata, bin.palette = "Polychrome::dark", bin.alpha = 1, bin.outline = TRUE,
      highlight.colname = "signif", signif.lwd = 0.5, plot.title = "Binned Manhattan Plot"
    )
    print(p4)
    dev.off()

    writeLines(c(
        '"BIOC_GGMANH_BINNED_MANHATTAN_PLOT":',
        paste0('    ggmanh: ', as.character(packageVersion('ggmanh')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binned_manhattan_plot.csv versions.yml
    """
}

workflow BIOC_GGMANH_BINNED_MANHATTAN_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ large_gwas_results.csv ] ]

    main:
    BIOC_GGMANH_BINNED_MANHATTAN_PLOT(ch_input)

    emit:
    tables   = BIOC_GGMANH_BINNED_MANHATTAN_PLOT.out.tables
    plots    = BIOC_GGMANH_BINNED_MANHATTAN_PLOT.out.plots
    objects  = BIOC_GGMANH_BINNED_MANHATTAN_PLOT.out.objects
    versions = BIOC_GGMANH_BINNED_MANHATTAN_PLOT.out.versions
}
