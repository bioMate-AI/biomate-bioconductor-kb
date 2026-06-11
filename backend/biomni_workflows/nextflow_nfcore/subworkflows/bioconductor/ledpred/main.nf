#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ledpred — step_by_step_svm_prediction
// Build an SVM model from genomic regions and features step-by-step, tune parameters, select features, evaluate performance, and score unknown sequences.
// Input: positive.bed, negative.bed, background.freq, TF.matrices, ngs.files, prediction_small.bed
// Container: quay.io/biocontainers/bioconductor-ledpred:1.44.0--r45hdfd78af_0
// R packages: LedPred
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ledpred:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("LedPred")
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
    
    library(LedPred)
    
    # Define input files from the working directory
    positive.regions <- "positive.bed"
    negative.regions <- "negative.bed"
    background.freq <- "background.freq"
    TF.matrices <- "TF.matrices"
    ngs.files <- "ngs.files"
    positive.bed <- "prediction_small.bed"
    
    # Verify that all required input files exist
    required_files <- c(positive.regions, negative.regions, background.freq, TF.matrices, ngs.files, positive.bed)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files:", paste(missing_files, collapse = ", ")))
    }
    
    # --- Map features to positive and negative CRMs to build the ---
    crm.feature.list <- mapFeaturesToCRMs(
      URL = 'http://ifbprod.aitorgonzalezlab.org/map_features_to_crms.php', 
      positive.bed = positive.regions, 
      negative.bed = negative.regions, 
      background.freqs = background.freq, 
      pssm = TF.matrices, 
      genome = "dm3", 
      ngs = ngs.files,  
      crm.feature.file = "vignette_crm.features.tab",  
      stderr.log.file = "vignette_stderr.log", 
      stdout.log.file = "vignette_stdout.log"
    )
    crm.features <- crm.feature.list\$crm.features
    
    # Save the mapped training features
    write.csv(crm.features, file = "mapped_crm_features.csv", row.names = TRUE)
    
    # --- Tune SVM cost and gamma parameters using cross-validation ---
    cost.vector <- c(1, 3, 10)
    gamma.vector <- c(1, 3, 10)
    c.g.obj <- mcTune(
      data = crm.features, 
      ranges = list(cost = cost.vector, gamma = gamma.vector), 
      kernel = 'linear', 
      file.prefix = "vignette"
    )
    cost <- c.g.obj\$e1071.tune.obj\$best.parameters\$cost
    gamma <- c.g.obj\$e1071.tune.obj\$best.parameters\$gamma
    
    # Save tuning results
    saveRDS(c.g.obj, file = "svm_parameter_tuning.rds")
    
    # --- Rank features using Recursive Feature Elimination (RFE) ---
    feature.ranking <- rankFeatures(
      data = crm.features, 
      cost = cost, 
      gamma = gamma, 
      kernel = 'linear', 
      file.prefix = "vignette"
    )
    write.csv(feature.ranking, file = "feature_ranking.csv", row.names = FALSE)
    
    # --- Determine the optimal number of features using Cohen's ---
    feature.nb.tuner.obj <- tuneFeatureNb(
      data = crm.features, 
      feature.ranking = feature.ranking, 
      kernel = 'linear', 
      cost = cost, 
      gamma = gamma, 
      file.prefix = "vignette"
    )
    saveRDS(feature.nb.tuner.obj, file = "feature_nb_tuning.rds")
    
    # Determine optimal feature number with a fallback if not resolved
    feature.nb <- feature.nb.tuner.obj\$best.feature.nb
    if (is.null(feature.nb) || is.na(feature.nb)) {
      feature.nb <- min(60, nrow(feature.ranking))
    }
    
    # --- Create the final SVM model ---
    model.obj <- createModel(
      data = crm.features, 
      cost = cost, 
      gamma = gamma, 
      feature.ranking = feature.ranking, 
      feature.nb = feature.nb, 
      file.prefix = "vignette"
    )
    saveRDS(model.obj, file = "final_svm_model.rds")
    
    # Calculate and save feature weights
    feature.weights <- as.data.frame(t(t(model.obj\$model\$coefs) %*% model.obj\$model\$SV))
    write.csv(feature.weights, file = "feature_weights.csv", row.names = TRUE)
    
    # --- Evaluate model performance with ROC and Precision-Recall ---
    probs.labels.list <- evaluateModelPerformance(
      data = crm.features, 
      feature.ranking = feature.ranking, 
      feature.nb = feature.nb, 
      cost = cost, 
      gamma = gamma, 
      file.prefix = "vignette"
    )
    saveRDS(probs.labels.list, file = "model_evaluation_probs.rds")
    
    # --- Map features to unknown sequences without negative regions ---
    prediction.crm.features.list <- mapFeaturesToCRMs(
      URL = 'http://ifbprod.aitorgonzalezlab.org/map_features_to_crms.php', 
      positive.bed = positive.bed, 
      pssm = TF.matrices, 
      background.freqs = background.freq, 
      genome = 'dm3', 
      ngs = ngs.files, 
      feature.ranking = feature.ranking, 
      feature.nb = feature.nb, 
      crm.feature.file = "vignette_pred.crm.features.tab", 
      stderr.log.file = "vignette_pred.stderr.log", 
      stdout.log.file = "vignette_pred.stdout.log"
    )
    prediction.crm.features <- prediction.crm.features.list\$crm.features
    write.csv(prediction.crm.features, file = "prediction_crm_features.csv", row.names = TRUE)
    
    # --- Score the unknown sequences using the trained model ---
    pred.test <- scoreData(
      data = prediction.crm.features, 
      model = model.obj, 
      score.file = "vignette_prediction.tab"
    )
    
    # Save final predictions
    write.csv(pred.test, file = "final_predictions.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION":',
        paste0('        ledpred: ', as.character(packageVersion("ledpred")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_svm_prediction.csv versions.yml
    """
}

workflow BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ positive.bed, negative.bed, background.freq, TF.matrices, ngs.files, prediction_small.bed ] ]

    main:
    BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION(ch_input)

    emit:
    tables   = BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION.out.tables
    plots    = BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION.out.plots
    objects  = BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION.out.objects
    versions = BIOC_LEDPRED_STEP_BY_STEP_SVM_PREDICTION.out.versions
}
