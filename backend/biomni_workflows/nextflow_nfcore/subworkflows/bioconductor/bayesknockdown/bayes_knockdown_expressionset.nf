#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BayesKnockdown — bayes_knockdown_expressionset
// Calculate posterior probabilities of relationships between a single predictor feature and other features using an ExpressionSet object.
// Input: expression_set.RData
// Container: quay.io/biocontainers/bioconductor-bayesknockdown:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BayesKnockdown, Biobase
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Biobase and the ExpressionSet
//  * 2. [Core Analysis] Subset the ExpressionSet if necessary
//  * 3. [Core Analysis] Run BayesKnockdown.es specifying the ExpressionSet and the predictor feature name

nextflow.enable.dsl = 2

process BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET {
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
    .bm_deps <- c("Biobase", "BayesKnockdown")
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
    library(Biobase)
    library(BayesKnockdown)
    
    # 1. Load the user-provided ExpressionSet object
    if (!file.exists("expression_set.RData")) {
      stop("Error: 'expression_set.RData' not found in the working directory.")
    }
    
    env <- new.env()
    load("expression_set.RData", envir = env)
    
    # Find the ExpressionSet object within the loaded environment
    es_obj <- NULL
    for (name in ls(env)) {
      if (inherits(env[[name]], "ExpressionSet")) {
        es_obj <- env[[name]]
        break
      }
    }
    
    if (is.null(es_obj)) {
      stop("Error: No ExpressionSet object found in 'expression_set.RData'.")
    }
    
    # 2. Identify the predictor feature (using the first feature)
    predictor_feature <- featureNames(es_obj)[1]
    
    # 3. Run BayesKnockdown.es
    result <- BayesKnockdown.es(es_obj, predictor_feature)
    
    # 4. Save meaningful results to output files
    # Save the posterior probabilities as a CSV table
    results_df <- data.frame(
      Feature = names(result),
      PosteriorProbability = as.numeric(result),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "bayes_knockdown_results.csv", row.names = FALSE)
    
    # Save the raw result vector as an RDS object
    saveRDS(result, "bayes_knockdown_results.rds")
    
    # Generate and save a barplot of the posterior probabilities
    pdf("bayes_knockdown_plot.pdf", width = 8, height = 6)
    barplot(
      result,
      las = 2,
      cex.names = 0.7,
      xlab = "Target Gene",
      ylab = "Posterior Probability",
      ylim = c(0, 1),
      main = paste("Posterior Probabilities of Relationship with", predictor_feature)
    )
    dev.off()

    writeLines(c(
        '"BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET":',
        paste0('    BayesKnockdown: ', as.character(packageVersion('BayesKnockdown')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayes_knockdown_expressionset.csv versions.yml
    """
}

workflow BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData ] ]

    main:
    BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET(ch_input)

    emit:
    tables   = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET.out.tables
    plots    = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET.out.plots
    objects  = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET.out.objects
    versions = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_EXPRESSIONSET.out.versions
}
