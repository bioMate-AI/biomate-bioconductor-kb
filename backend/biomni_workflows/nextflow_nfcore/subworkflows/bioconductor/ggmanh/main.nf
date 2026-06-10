#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggmanh — standard_and_rescaled_manhattan_plot
// Preprocess and plot standard or rescaled Manhattan plots from GWAS summary statistics, with optional point highlighting and labeling.
// Input: gwas_results.csv
// Container: quay.io/biocontainers/bioconductor-ggmanh:1.14.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggmanh, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format chromosome column as a factor
//  * 2. [Core Analysis] Preprocess data using manhattan_data_preprocess()
//  * 3. [Visualization & Output] Generate the plot using manhattan_plot()

nextflow.enable.dsl = 2

process BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
            library(ggmanh)
            library(ggplot2)
            
            # Read the user input file
            if (!file.exists("gwas_results.csv")) {
              stop("Error: 'gwas_results.csv' not found in the working directory.")
            }
            
            simdata <- read.csv("gwas_results.csv", stringsAsFactors = FALSE)
            
            # Standardize column names to match the vignette's expected names
            colnames(simdata)[tolower(colnames(simdata)) %in% c("chr", "chromosome", "chrom")] <- "chromosome"
            colnames(simdata)[tolower(colnames(simdata)) %in% c("pos", "position", "bp")] <- "position"
            colnames(simdata)[tolower(colnames(simdata)) %in% c("p", "p.value", "pvalue", "pval")] <- "P.value"
            
            # Clean chromosome values (e.g., strip "chr" prefix if present)
            simdata\$chromosome <- gsub("(?i)chr", "", as.character(simdata\$chromosome), perl = TRUE)
            
            # 1. Format chromosome column as a factor
            simdata\$chromosome <- factor(simdata\$chromosome, c(1:22, "X"))
            
            # Prepare annotation columns to avoid errors during plotting
            sig <- simdata\$P.value < 5e-07
            simdata\$label <- ""
            if (any(sig, na.rm = TRUE)) {
              simdata\$label[which(sig)] <- sprintf("Label: %i", 1:sum(sig, na.rm = TRUE))
            }
            
            simdata\$label2 <- ""
            i <- (simdata\$chromosome == 5) & (simdata\$P.value < 5e-8)
            if (any(i, na.rm = TRUE)) {
              simdata\$label2[which(i)] <- paste("Chromosome 5 label", 1:sum(i, na.rm = TRUE))
            }
            
            simdata\$color <- "Not Significant"
            simdata\$color[which(simdata\$P.value <= 5e-8)] <- "Significant"
            highlight_colormap <- c("Not Significant" = "grey", "Significant" = "black")
            
            # Open PDF device to save the plots
            pdf("manhattan_plots.pdf", width = 10, height = 6)
            
            # 2. Generate standard Manhattan plot
            g <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", plot.title = "Simulated P.Values", y.label = "P")
            print(g)
            
            # 3. Generate rescaled Manhattan plot
            g <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", plot.title = "Simulated P.Values - Significant", rescale = TRUE)
            print(g)
            
            # 4. Preprocess data using manhattan_data_preprocess()
            mpdata <- manhattan_data_preprocess(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
            
            # Save preprocessed data object
            saveRDS(mpdata, "preprocessed_manhattan_data.rds")
            
            # 5. Generate plots using preprocessed data with labels
            g <- manhattan_plot(x = mpdata, label.colname = "label", plot.title = "Simulated P.Values with labels")
            print(g)
            
            g <- manhattan_plot(x = mpdata, label.colname = "label2", label.font.size = 2, plot.title = "Simulated P.Values with labels", max.overlaps = Inf, force = 5)
            print(g)
            
            # 6. Preprocess with custom highlighting
            tmp <- manhattan_data_preprocess(
              simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position",
              highlight.colname = "color", highlight.col = highlight_colormap
            )
            
            g <- manhattan_plot(tmp, plot.title = "Highlight Points", color.by.highlight = TRUE)
            print(g)
            
            # 7. Zoom into Chromosome 5
            tryCatch({
              g_zoom <- manhattan_plot(simdata, chromosome = 5, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
              print(g_zoom)
            }, error = function(e) {
              warning("Could not plot chromosome 5 zoom: ", e\$message)
            })
            
            # Close PDF device
            dev.off()
            
            cat("Pipeline completed successfully. Outputs saved to 'manhattan_plots.pdf' and 'preprocessed_manhattan_data.rds'.\n")

    writeLines(c(
        '"BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT":',
        paste0('    ggmanh: ', as.character(packageVersion('ggmanh')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_and_rescaled_manhattan_plot.csv versions.yml
    """
}

workflow BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gwas_results.csv ] ]

    main:
    BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT(ch_input)

    emit:
    tables   = BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT.out.tables
    plots    = BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT.out.plots
    objects  = BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT.out.objects
    versions = BIOC_GGMANH_STANDARD_AND_RESCALED_MANHATTAN_PLOT.out.versions
}
