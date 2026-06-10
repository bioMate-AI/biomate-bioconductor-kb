#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dce — differential_causal_effect_estimation
// Compute and visualize differential causal effects on a biological network using gene expression data from two conditions.
// Input: network.gml, expression_control.csv, expression_treatment.csv
// Container: quay.io/biocontainers/bioconductor-dce:1.10.0--r43hdfd78af_0
// R packages: cowplot, curatedtcgadata, dce, ggplot2, igraph, SummarizedExperiment, TCGAutils
// Bioconductor: 3.20 | R: 4.4
// Requires: dce, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the network topology and expression datasets
//  * 2. [Core Analysis] Compute differential causal effects using the dce function
//  * 3. [Visualization & Output] Visualize the resulting differential causal network using the plot function

nextflow.enable.dsl = 2

process BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION {
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
    .bm_deps <- c("cowplot", "curatedtcgadata", "dce", "ggplot2", "igraph", "SummarizedExperiment", "TCGAutils")
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
    library(dce)
    library(igraph)
    
    # 1. Load the network topology and expression datasets
    # Read the network graph from GML format
    graph <- igraph::read_graph("network.gml", format = "gml")
    
    # Read gene expression datasets (samples as rows, genes as columns)
    df.expr.wt <- read.csv("expression_control.csv", row.names = 1, check.names = FALSE)
    df.expr.mt <- read.csv("expression_treatment.csv", row.names = 1, check.names = FALSE)
    
    # Ensure datasets are data frames
    df.expr.wt <- as.data.frame(df.expr.wt)
    df.expr.mt <- as.data.frame(df.expr.mt)
    
    # 2. Compute differential causal effects using the dce function
    res <- dce(graph, df.expr.wt, df.expr.mt)
    
    # 3. Visualize the resulting differential causal network using the plot function
    pdf("dce_plot.pdf", width = 10, height = 8)
    plot(res)
    dev.off()
    
    # Save the raw results object
    saveRDS(res, "dce_results.rds")
    
    # Export the results as a CSV table
    res_df <- tryCatch({
      as.data.frame(res)
    }, error = function(e) {
      # Fallback if direct coercion is not supported
      summary(res)
    })
    write.csv(res_df, "dce_results.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION":',
        paste0('    dce: ', as.character(packageVersion('dce')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_causal_effect_estimation.csv versions.yml
    """
}

workflow BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.gml, expression_control.csv, expression_treatment.csv ] ]

    main:
    BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION.out.tables
    plots    = BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION.out.plots
    objects  = BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION.out.objects
    versions = BIOC_DCE_DIFFERENTIAL_CAUSAL_EFFECT_ESTIMATION.out.versions
}
