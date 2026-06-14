#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OPWeight — decomposed_opw
// Manually compute rank probabilities and weights step-by-step to allow custom modeling, parallelization, or detailed inspection of intermediate parameters.
// Input: de_res_air$pvalue, de_res_air$baseMean
// Container: quay.io/biocontainers/bioconductor-opweight:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OPWeight, cowplot, ggplot2, qvalue, tibble
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transform p-values to test statistics and ensure filter statistics are positive
//  * 2. [Core Analysis] Estimate the proportion of true null hypotheses using the qvalue package
//  * 3. [Core Analysis] Fit a Box-Cox regression model between filter statistics and test statistics
//  * 4. [Core Analysis] Estimate the mean test effect and mean filter effect for the true alternatives
//  * 5. [Core Analysis] Compute the rank probabilities using prob_rank_givenEffect
//  * 6. [Core Analysis] Compute continuous weights using weight_continuous
//  * 7. [Core Analysis] Perform multiple testing correction using adjusted p-values or run the opw function with pre-computed weights

nextflow.enable.dsl = 2

process BIOC_OPWEIGHT_DECOMPOSED_OPW {
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
    .bm_deps <- c("OPWeight", "ggplot2", "cowplot", "tibble", "qvalue", "MASS")
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
    library("OPWeight")
    library("ggplot2")
    library("cowplot")
    library("tibble")
    library("qvalue")
    library("MASS")
    
    # Helper function to robustly read input files
    read_vector <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file not found:", filepath))
      }
      val <- tryCatch({
        readRDS(filepath)
      }, error = function(e) {
        tryCatch({
          scan(filepath, quiet = TRUE)
        }, error = function(e2) {
          tryCatch({
            df <- read.csv(filepath, header = FALSE)
            df[[1]]
          }, error = function(e3) {
            stop(paste("Could not read file:", filepath))
          })
        })
      })
      return(as.numeric(val))
    }
    
    # 1. Read user input files
    pvals_raw <- read_vector("de_res_air\$pvalue")
    filters_raw <- read_vector("de_res_air\$baseMean")
    
    # Preprocess to remove NAs and handle boundary cases
    keep <- !is.na(pvals_raw) & !is.na(filters_raw)
    pvals <- pvals_raw[keep]
    filters_raw <- filters_raw[keep]
    
    # Avoid exact zeros in p-values to prevent infinite test statistics
    pvals[pvals == 0] <- .Machine\$double.eps
    
    # Transform p-values to test statistics
    tests <- qnorm(pvals/2, lower.tail = FALSE)
    filters <- filters_raw + .0001    # to ensure filters are positive for the box-cox
    
    # Ensure all values are finite
    valid <- is.finite(tests) & is.finite(filters)
    pvals <- pvals[valid]
    filters <- filters[valid]
    tests <- tests[valid]
    
    # Formulate a data set
    Data <- tibble(pvals, filters)
    OD <- Data[order(Data\$filters, decreasing=TRUE), ]
    Ordered.pvalue <- OD\$pvals
    
    # Estimate the true null and alternative test sizes
    m <- length(Data\$pvals)
    nullProp <- qvalue(Data\$pvals, pi0.method="bootstrap")\$pi0
    m0 <- ceiling(nullProp*m)
    m1 <- m - m0
    
    # Fit box-cox regression and save the plot
    pdf("boxcox_plot.pdf")
    bc <- boxcox(filters ~ tests)
    dev.off()
    
    lambda <- bc\$x[which.max(bc\$y)]
    model <- lm(filters^lambda ~ tests)
    
    # Estimated test effects of the true alternatives
    test_effect <- if(m1 == 0) {
      0
    } else {
      sort(tests, decreasing = TRUE)[1:m1]
    } # two-tailed test
    
    # For the continuous effects estimated mean effects
    mean_testEffect <- mean(test_effect, na.rm = TRUE)
    mean_filterEffect <- model\$coef[[1]] + model\$coef[[2]]*mean_testEffect
    
    # Compute rank probabilities
    set.seed(123)
    prob_cont <- sapply(1:m, prob_rank_givenEffect, et = mean_filterEffect,
                        ey = mean_filterEffect, nrep = 1000, m0 = m0, m1 = m1)
    
    # Compute continuous weights
    wgt <- weight_continuous(alpha = .1, et = mean_testEffect, m = m, 
                             delInterval = .01, ranksProb = prob_cont)
    
    # Perform multiple testing correction using adjusted p-values
    alpha <- .1
    padj <- p.adjust(Ordered.pvalue/wgt, method = "BH")
    rejections_list <- OD[which((padj <= alpha) == TRUE), ]
    n_rejections <- dim(rejections_list)[1]
    
    # Run the opw function with pre-computed weights
    opw_results2 <- opw(pvalue = pvals, filter = filters, weight = wgt, 
                        effectType = "continuous", alpha = .1, method = "BH")
    
    # Save meaningful results to files
    write.csv(rejections_list, "rejections_list.csv", row.names = FALSE)
    saveRDS(opw_results2, "opw_results2.rds")
    
    # Save summary metrics
    summary_metrics <- data.frame(
      Metric = c("total_tests", "null_proportion", "m0", "m1", "lambda", "mean_test_effect", "mean_filter_effect", "n_rejections", "opw_rejections"),
      Value = c(m, nullProp, m0, m1, lambda, mean_testEffect, mean_filterEffect, n_rejections, opw_results2\$rejections)
    )
    write.csv(summary_metrics, "summary_metrics.csv", row.names = FALSE)
    
    # Generate and save diagnostic plots
    testRanks <- 1:m
    dat <- tibble(testRanks, probs = prob_cont, weights = wgt)
    
    p_prob <- ggplot(dat, aes(x = testRanks, y = probs)) + 
      geom_point(size = .5, col="firebrick4") + 
      labs(x = "Test rank" , y = "p(rank | effect)")
    
    p_weight <- ggplot(dat, aes(x = testRanks, y = weights)) + 
      geom_point(size = .5, col="firebrick4") + 
      labs(x = "Test rank" , y = "Weight")
    
    pdf("weights_vs_ranks.pdf", width = 10, height = 5)
    print(plot_grid(p_prob, p_weight, labels = c("a", "b")))
    dev.off()

    writeLines(c(
        '"BIOC_OPWEIGHT_DECOMPOSED_OPW":',
        paste0('    OPWeight: ', as.character(packageVersion('OPWeight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decomposed_opw.csv versions.yml
    """
}

workflow BIOC_OPWEIGHT_DECOMPOSED_OPW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ de_res_air$pvalue, de_res_air$baseMean ] ]

    main:
    BIOC_OPWEIGHT_DECOMPOSED_OPW(ch_input)

    emit:
    tables   = BIOC_OPWEIGHT_DECOMPOSED_OPW.out.tables
    plots    = BIOC_OPWEIGHT_DECOMPOSED_OPW.out.plots
    objects  = BIOC_OPWEIGHT_DECOMPOSED_OPW.out.objects
    versions = BIOC_OPWEIGHT_DECOMPOSED_OPW.out.versions
}
