#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gaga — class_prediction
// Predict the group/class of new samples using a fitted GaGa model.
// Input: training_expression.csv, new_expression.csv, training_groups.csv
// Container: quay.io/biocontainers/bioconductor-gaga:2.56.0--r45h01b2380_0
// Requires: gaga
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the GaGa model on training data using fitGG and parest. 2. Predict the class of new samples and obtain posterior probabilities

nextflow.enable.dsl = 2

process BIOC_GAGA_CLASS_PREDICTION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(gaga)
    
    # -------------------------------------------------------------------------
    # 1. Read User Input Files
    # -------------------------------------------------------------------------
    # Read the normalized expression matrix for training samples
    training_expr <- as.matrix(read.csv("training_expression.csv", row.names = 1))
    
    # Read the expression matrix for new samples to classify
    new_expr <- as.matrix(read.csv("new_expression.csv", row.names = 1))
    
    # Read the group labels for training samples
    training_groups_df <- read.csv("training_groups.csv", stringsAsFactors = FALSE)
    
    # Extract the group vector
    if ("group" %in% colnames(training_groups_df)) {
      groups <- as.character(training_groups_df\$group)
    } else {
      groups <- as.character(training_groups_df[[1]])
    }
    
    # -------------------------------------------------------------------------
    # 2. Define Expression Patterns
    # -------------------------------------------------------------------------
    unique_groups <- unique(groups)
    if (length(unique_groups) != 2) {
      stop("The GaGa class prediction workflow requires exactly 2 distinct groups in training_groups.csv")
    }
    
    # Define the 2-class patterns matrix (Pattern 0: equal, Pattern 1: differential)
    patterns <- matrix(c(0, 0, 0, 1), 2, 2)
    colnames(patterns) <- unique_groups
    
    # -------------------------------------------------------------------------
    # 3. Fit the GaGa Model (fitGG and parest)
    # -------------------------------------------------------------------------
    message("Fitting GaGa model via Gibbs sampling...")
    gg1 <- fitGG(training_expr, groups, patterns=patterns, nclust=1, method='Gibbs', B=1000, trace=FALSE)
    
    message("Estimating posterior parameters...")
    gg1 <- parest(gg1, x=training_expr, groups, burnin=100, alpha=.05)
    
    # -------------------------------------------------------------------------
    # 4. Predict Class of New Samples (classpred)
    # -------------------------------------------------------------------------
    message("Predicting class for the new samples...")
    # Dynamically set ngene to be at most the number of available genes
    ngene_val <- min(50, nrow(training_expr))
    
    predicted_classes <- integer(ncol(new_expr))
    pos_prob_group1 <- numeric(ncol(new_expr))
    pos_prob_group2 <- numeric(ncol(new_expr))
    
    for (i in seq_len(ncol(new_expr))) {
      pred <- classpred(gg1, xnew=new_expr[, i], x=training_expr, groups=groups, ngene=ngene_val, prgroups=c(.5,.5))
      predicted_classes[i] <- pred\$d
      pos_prob_group1[i] <- pred\$posgroups[1]
      pos_prob_group2[i] <- pred\$posgroups[2]
    }
    
    # -------------------------------------------------------------------------
    # 5. Save Outputs and Generate Diagnostic Plots
    # -------------------------------------------------------------------------
    # Save the fitted model object
    saveRDS(gg1, "fitted_gaga_model.rds")
    
    # Save prediction results to a CSV file
    prediction_results <- data.frame(
      Predicted_Class = predicted_classes,
      Posterior_Prob_Group1 = pos_prob_group1,
      Posterior_Prob_Group2 = pos_prob_group2
    )
    write.csv(prediction_results, "class_predictions.csv", row.names = FALSE)
    
    # Generate and save goodness-of-fit diagnostic plots
    pdf("goodness_of_fit_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2, 2))
    tryCatch({
      checkfit(gg1, x = training_expr, groups, type = 'data', main = 'Data Fit')
      checkfit(gg1, x = training_expr, groups, type = 'shape', main = 'Shape Parameter Fit')
      checkfit(gg1, x = training_expr, groups, type = 'mean', main = 'Mean Parameter Fit')
      checkfit(gg1, x = training_expr, groups, type = 'shapemean', main = 'Joint Fit', xlab = 'Mean', ylab = '1/sqrt(CV)')
    }, error = function(e) {
      warning("Some diagnostic plots could not be generated: ", e\$message)
    })
    dev.off()
    
    message("Workflow completed successfully. Outputs saved to 'fitted_gaga_model.rds', 'class_predictions.csv', and 'goodness_of_fit_plots.pdf'.")

    writeLines(c(
        '"BIOC_GAGA_CLASS_PREDICTION":',
        paste0('    gaga: ', as.character(packageVersion('gaga')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_class_prediction.csv versions.yml
    """
}

workflow BIOC_GAGA_CLASS_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ training_expression.csv, new_expression.csv, training_groups.csv ] ]

    main:
    BIOC_GAGA_CLASS_PREDICTION(ch_input)

    emit:
    tables   = BIOC_GAGA_CLASS_PREDICTION.out.tables
    plots    = BIOC_GAGA_CLASS_PREDICTION.out.plots
    objects  = BIOC_GAGA_CLASS_PREDICTION.out.objects
    versions = BIOC_GAGA_CLASS_PREDICTION.out.versions
}
