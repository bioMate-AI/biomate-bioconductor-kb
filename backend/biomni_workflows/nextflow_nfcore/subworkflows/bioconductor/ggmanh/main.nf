#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggmanh
// Manhattan plot and QQ Plot are commonly used to visualize the end result of Genome Wide Association 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggmanh/inst/doc/ggmanh.R
// Upstream  : BiocManager
// Downstream: none
//
// Install: BiocManager::install("ggmanh")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGMANH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggmanh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggmanh:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggmanh:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggmanh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggmanh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggmanh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggmanh)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, sample, rbeta, chromosome, position
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>",
      fig.width = 7,
      fig.height = 4
    )
    set.seed(1000)

    nsim <- 50000

    simdata <- data.frame(
      "chromosome" = sample(c(1:22,"X"), size = nsim, replace = TRUE),
      "position" = sample(1:100000000, size = nsim),
      "P.value" = rbeta(nsim, shape1 = 5, shape2 = 1)^7
    )

    # --- Showsimdata [] ---
    # Key functions: ggmanh
    head(simdata)
    simdata$chromosome <- factor(simdata$chromosome, c(1:22,"X"))

    # --- Manh Minimum [] ---
    # Key functions: manhattan_plot, chromosome, position, rep, sample, rnorm
    g <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", plot.title = "Simulated P.Values", y.label = "P")
    g
    tmpdata <- data.frame(
      "chromosome" = c(rep(5, 10), rep(21, 5)),
      "position" = c(sample(250000:250100, 10, replace = FALSE), sample(590000:600000, 5, replace = FALSE)),
      "P.value" = c(10^-(rnorm(10, 100, 3)), 10^-rnorm(5, 9, 1))
    )

    simdata <- rbind(simdata, tmpdata)
    simdata$chromosome <- factor(simdata$chromosome, c(1:22,"X"))

    # --- Manh Badscale [] ---
    # Key functions: manhattan_plot, chromosome, position
    g <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", plot.title = "Simulated P.Values - Significant", rescale = FALSE)
    g
    g <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", plot.title = "Simulated P.Values - Significant", rescale = TRUE)
    g

    # --- Label Data [] ---
    # Key functions: manhattan_data_preprocess, manhattan_plot, chromosome, position, label, label2
    sig <- simdata$P.value < 5e-07

    simdata$label <- ""
    simdata$label[sig] <- sprintf("Label: %i", 1:sum(sig))
    simdata$label2 <- ""
    i <- (simdata$chromosome == 5) & (simdata$P.value < 5e-8)
    simdata$label2[i] <- paste("Chromosome 5 label", 1:sum(i))

    mpdata <- manhattan_data_preprocess(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")

    g <- manhattan_plot(x = mpdata, label.colname = "label", plot.title = "Simulated P.Values with labels")
    g

    g <- manhattan_plot(x = mpdata, label.colname = "label2", label.font.size = 2, plot.title = "Simulated P.Values with labels", max.overlaps = Inf, force = 5)

    # --- Highlight Chromosome [] ---
    # Key functions: manhattan_data_preprocess, manhattan_plot, grey, black, chromosome, position, color, binned_manhattan_plot
    simdata$color <- "Not Significant"
    simdata$color[simdata$P.value <= 5e-8] <- "Significant"

    highlight_colormap <- c("Not Significant" = "grey", "Significant" = "black")

    tmp <- manhattan_data_preprocess(
      simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position",
      highlight.colname = "color", highlight.col = highlight_colormap
    )

    manhattan_plot(simdata, chromosome = 5, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")

    ## -----------------------------------------------------------------------------
    binned_manhattan_plot(simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggmanh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggmanh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggmanh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGMANH:", paste0("    ggmanh: ", packageVersion("ggmanh"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggmanh_results.csv
    touch ${prefix}_ggmanh_output.rds
    echo "BIOC_GGMANH:" > versions.yml
    echo "    ggmanh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGMANH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGMANH(ch_input)

    emit:
    results  = BIOC_GGMANH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGMANH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGMANH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGMANH.out.versions  // channel: path(versions.yml)
}
