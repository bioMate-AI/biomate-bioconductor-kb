#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCOBRA — performance_evaluation_and_plotting
// Programmatically calculate and plot performance metrics (TPR, FDR, ROC, overlap) for ranking and binary classification methods.
// Input: Data frames containing p-values, adjusted p-values, scores, and ground truth
// Container: quay.io/biocontainers/bioconductor-icobra:1.38.0--r45hdfd78af_0
// R packages: ggplot2, iCOBRA
// Bioconductor: 3.20 | R: 4.4
// Requires: iCOBRA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and example data (or user data formatted as a COBRAData object)
//  * 2. [Core Analysis] Calculate adjusted p-values if missing using calculate_adjp
//  * 3. [Core Analysis] Calculate performance metrics using calculate_performance
//  * 4. [Visualization & Output] Prepare data for plotting using prepare_data_for_plot
//  * 5. [Visualization & Output] Generate performance plots using plot_tpr, plot_fdrtprcurve, and plot_overlap

nextflow.enable.dsl = 2

process BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ggplot2", "iCOBRA")
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
        
    library(iCOBRA)
    
    # Read user input files from the working directory
    pval <- if (file.exists("pval.csv")) read.csv("pval.csv", row.names = 1, check.names = FALSE) else data.frame()
    padj <- if (file.exists("padj.csv")) read.csv("padj.csv", row.names = 1, check.names = FALSE) else data.frame()
    score <- if (file.exists("score.csv")) read.csv("score.csv", row.names = 1, check.names = FALSE) else data.frame()
    truth <- if (file.exists("truth.csv")) read.csv("truth.csv", row.names = 1, check.names = FALSE) else data.frame()
    
    # Construct COBRAData object from user input
    cobradata_example <- COBRAData(pval = pval, padj = padj, score = score, truth = truth)
    class(cobradata_example)
    cobradata_example
    
    # Calculate adjusted p-values if missing
    cobradata_example <- calculate_adjp(cobradata_example)
    
    # Determine truth columns dynamically to avoid hardcoding
    bin_truth <- if ("status" %in% colnames(truth)) "status" else if (ncol(truth) > 0) colnames(truth)[1] else "status"
    con_truth <- if ("logFC" %in% colnames(truth)) "logFC" else if (ncol(truth) > 1) colnames(truth)[2] else bin_truth
    
    # Calculate performance metrics
    cobraperf <- calculate_performance(cobradata_example, binary_truth = bin_truth, 
                                      cont_truth = con_truth, splv = "none",
                                      maxsplit = 4)
    slotNames(cobraperf)
    
    # Prepare data for plotting
    cobraplot <- prepare_data_for_plot(cobraperf, colorscheme = "Dark2", 
                                      facetted = TRUE)
    
    # Generate and save performance plots
    pdf("cobra_performance_plots.pdf", width = 7, height = 5)
    print(plot_tpr(cobraplot))
    print(plot_fdrtprcurve(cobraplot))
    plot_overlap(cobraplot)
    dev.off()
    
    # Save performance and plot objects
    saveRDS(cobraperf, "cobraperf.rds")
    saveRDS(cobraplot, "cobraplot.rds")

    writeLines(c(
        '"BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING":',
        paste0('    iCOBRA: ', as.character(packageVersion('iCOBRA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_performance_evaluation_and_plotting.csv versions.yml
    """
}

workflow BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Data frames containing p-values, adjusted p-values, scores, and ground truth ] ]

    main:
    BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING(ch_input)

    emit:
    tables   = BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING.out.tables
    plots    = BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING.out.plots
    objects  = BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING.out.objects
    versions = BIOC_ICOBRA_PERFORMANCE_EVALUATION_AND_PLOTTING.out.versions
}
