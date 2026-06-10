#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BayesKnockdown — bayes_knockdown_matrix
// Calculate posterior probabilities of relationships between a single predictor variable and multiple target variables using numeric matrices.
// Input: predictor_vector.csv, targets_matrix.csv
// Container: quay.io/biocontainers/bioconductor-bayesknockdown:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BayesKnockdown
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Run BayesKnockdown with the predictor vector, target matrix, and optional prior
//  * 3. [Visualization & Output] Visualize the posterior probabilities using a barplot

nextflow.enable.dsl = 2

process BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # 1. Load the package
        library(BayesKnockdown)
        
        # 2. Read the user input files robustly
        if (!file.exists("predictor_vector.csv")) {
          stop("Error: predictor_vector.csv not found in the working directory.")
        }
        if (!file.exists("targets_matrix.csv")) {
          stop("Error: targets_matrix.csv not found in the working directory.")
        }
        
        # Read predictor vector
        predictor_raw <- read.csv("predictor_vector.csv", header = FALSE, stringsAsFactors = FALSE)
        # If the first row contains non-numeric values, treat it as a header and re-read
        if (any(is.na(suppressWarnings(as.numeric(predictor_raw[1, ]))))) {
          predictor_raw <- read.csv("predictor_vector.csv", header = TRUE, stringsAsFactors = FALSE)
        }
        predictor_vector <- as.numeric(unlist(predictor_raw))
        
        # Read targets matrix (rows = genes, columns = samples)
        targets_df <- tryCatch({
          read.csv("targets_matrix.csv", row.names = 1, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
        }, error = function(e) {
          read.csv("targets_matrix.csv", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
        })
        targets_matrix <- as.matrix(targets_df)
        class(targets_matrix) <- "numeric"
        
        # Validate dimensions
        if (length(predictor_vector) != ncol(targets_matrix)) {
          stop(sprintf("Dimension mismatch: predictor vector has length %d, but targets matrix has %d columns (samples).", 
                       length(predictor_vector), ncol(targets_matrix)))
        }
        
        # 3. Run BayesKnockdown with the predictor vector, target matrix, and prior
        kdResult <- BayesKnockdown(predictor_vector, targets_matrix, prior=0.0005);
        kdResult;
        
        # 4. Visualize the posterior probabilities using a barplot and save to PDF
        pdf("bayes_knockdown_barplot.pdf", width = 8, height = 6)
        barplot(kdResult, names.arg="", xlab="Target Gene",
                ylab="Posterior Probability", ylim=c(0,1));
        dev.off()
        
        # 5. Save results to CSV and RDS
        target_names <- names(kdResult)
        if (is.null(target_names)) {
          target_names <- paste0("Target_", seq_along(kdResult))
        }
        
        results_df <- data.frame(
          Target_Gene = target_names,
          Posterior_Probability = as.numeric(kdResult),
          stringsAsFactors = FALSE
        )
        write.csv(results_df, "bayes_knockdown_results.csv", row.names = FALSE)
        saveRDS(kdResult, "bayes_knockdown_results.rds")

    writeLines(c(
        '"BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX":',
        paste0('    BayesKnockdown: ', as.character(packageVersion('BayesKnockdown')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayes_knockdown_matrix.csv versions.yml
    """
}

workflow BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ predictor_vector.csv, targets_matrix.csv ] ]

    main:
    BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX(ch_input)

    emit:
    tables   = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX.out.tables
    plots    = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX.out.plots
    objects  = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX.out.objects
    versions = BIOC_BAYESKNOCKDOWN_BAYES_KNOCKDOWN_MATRIX.out.versions
}
