#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BayesKnockdown — bayes_knockdown_diff_exp
// Test for differential expression in a set of variables between two experimental conditions.
// Input: condition1_matrix.csv, condition2_matrix.csv
// Container: quay.io/biocontainers/bioconductor-bayesknockdown:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BayesKnockdown
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare expression matrices for both conditions
//  * 2. [Core Analysis] Run BayesKnockdown.diffExp to calculate posterior probabilities of differential expression
//  * 3. [Visualization & Output] Visualize the posterior probabilities using a barplot

nextflow.enable.dsl = 2

process BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP {
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
    .bm_deps <- c("BayesKnockdown")
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
    library(BayesKnockdown)
    
    # 1. Prepare expression matrices for both conditions
    # Read the user input files (genes as rows, samples as columns)
    y1_df <- read.csv("condition1_matrix.csv", row.names = 1, check.names = FALSE)
    y2_df <- read.csv("condition2_matrix.csv", row.names = 1, check.names = FALSE)
    
    y1 <- as.matrix(y1_df)
    y2 <- as.matrix(y2_df)
    
    # Align genes (rows) between both matrices to ensure consistency
    common_genes <- intersect(rownames(y1), rownames(y2))
    if (length(common_genes) == 0) {
      stop("Error: No common genes found between condition1_matrix.csv and condition2_matrix.csv")
    }
    y1 <- y1[common_genes, , drop = FALSE]
    y2 <- y2[common_genes, , drop = FALSE]
    
    # 2. Run BayesKnockdown.diffExp to calculate posterior probabilities of differential expression
    diffExpResult <- BayesKnockdown.diffExp(y1, y2)
    
    # 3. Visualize the posterior probabilities using a barplot and save to PDF
    pdf("diff_exp_barplot.pdf", width = 10, height = 6)
    barplot(diffExpResult, names.arg = "", xlab = "Target Gene",
            ylab = "Posterior Probability", ylim = c(0, 1))
    dev.off()
    
    # 4. Write named output files for the meaningful results
    # Save RDS object
    saveRDS(diffExpResult, file = "diff_exp_results.rds")
    
    # Save CSV table of results
    results_df <- data.frame(
      Gene = names(diffExpResult),
      PosteriorProbability = as.numeric(diffExpResult),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, file = "diff_exp_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP":',
        paste0('    BayesKnockdown: ', as.character(packageVersion('BayesKnockdown')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayes_knockdown_diff_exp.csv versions.yml
    """
}

workflow BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ condition1_matrix.csv, condition2_matrix.csv ] ]

    main:
    BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP(ch_input)

    emit:
    tables   = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP.out.tables
    plots    = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP.out.plots
    objects  = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP.out.objects
    versions = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_DIFF_EXP.out.versions
}
