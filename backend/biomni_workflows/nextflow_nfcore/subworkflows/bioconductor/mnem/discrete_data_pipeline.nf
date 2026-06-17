#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mnem — discrete_data_pipeline
// Perform causal network and subpopulation inference on binary/discrete single-cell perturbation data (1 for effect, 0 for no effect) by specifying false positive
// Input: datadisc.csv
// Container: quay.io/biocontainers/bioconductor-mnem:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mnem
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run mixture NEM on discrete data using mnem with method = "disc" and specified false positive/false negative rates (fpfn)
//  * 2. [Visualization & Output] Plot the resulting mixture NEM components and cell assignments using plot

nextflow.enable.dsl = 2

process BIOC_MNEM_DISCRETE_DATA_PIPELINE {
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
    .bm_deps <- c("mnem")
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
    
    # Load required library
    library(mnem)
    
    # Check if the required input file exists
    if (!file.exists("datadisc.csv")) {
      stop("Error: Input file 'datadisc.csv' not found in the working directory.")
    }
    
    # Read the discrete data matrix
    # Rows: E-genes (features), Columns: cells (perturbed S-genes)
    datadisc_df <- read.csv("datadisc.csv", row.names = 1, check.names = FALSE)
    datadisc <- as.matrix(datadisc_df)
    
    # Define parameters required by the documented code
    # We assume a default of 3 mixture components (k = 3) and 5 EM starts.
    # These can be adjusted by the user as needed.
    mw <- rep(1/3, 3)
    starts <- 5
    
    # 1. Run mixture NEM on discrete data using mnem with method = "disc" and specified fpfn rates
    result_disc <- mnem(datadisc, k = length(mw), search = "greedy",
                        starts = starts, method = "disc", fpfn = c(0.1,0.1))
    
    # 2. Plot the resulting mixture NEM components and cell assignments
    pdf("result_disc_plot.pdf", width = 12, height = 8)
    plot(result_disc)
    dev.off()
    
    # Save the main mnem result object
    saveRDS(result_disc, "result_disc.rds")
    
    # Extract and save cell responsibilities (posterior probabilities / affinities)
    postprobs <- getAffinity(result_disc\$probs, mw = result_disc\$mw)
    write.csv(postprobs, "cell_responsibilities.csv", row.names = TRUE)
    
    # Save inferred mixture weights
    mw_df <- data.frame(
      Component = seq_along(result_disc\$mw),
      MixtureWeight = result_disc\$mw
    )
    write.csv(mw_df, "mixture_weights.csv", row.names = FALSE)
    
    # Save convergence log-likelihoods
    lls_df <- data.frame(
      Iteration = seq_along(result_disc\$ll),
      LogLikelihood = result_disc\$ll
    )
    write.csv(lls_df, "log_likelihoods.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MNEM_DISCRETE_DATA_PIPELINE":',
        paste0('    mnem: ', as.character(packageVersion('mnem')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discrete_data_pipeline.csv versions.yml
    """
}

workflow BIOC_MNEM_DISCRETE_DATA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datadisc.csv ] ]

    main:
    BIOC_MNEM_DISCRETE_DATA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MNEM_DISCRETE_DATA_PIPELINE.out.tables
    plots    = BIOC_MNEM_DISCRETE_DATA_PIPELINE.out.plots
    objects  = BIOC_MNEM_DISCRETE_DATA_PIPELINE.out.objects
    versions = BIOC_MNEM_DISCRETE_DATA_PIPELINE.out.versions
}
