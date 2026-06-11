#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ledpred — all_in_one_svm_prediction
// Build an SVM model and score unknown sequences using the all-in-one LedPred wrapper function.
// Input: positive.bed, negative.bed, background.freq, TF.matrices, ngs.files, prediction_small.bed
// Container: quay.io/biocontainers/bioconductor-ledpred:1.44.0--r45hdfd78af_0
// R packages: LedPred
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION {
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
    
    # Load required library
    library(LedPred)
    
    # Define input files from the working directory
    positive.bed <- "positive.bed"
    negative.bed <- "negative.bed"
    background.freqs <- "background.freq"
    TF.matrices <- "TF.matrices"
    ngs.files <- "ngs.files"
    prediction_small.bed <- "prediction_small.bed"
    
    # Verify all required files exist
    required_files <- c(positive.bed, negative.bed, background.freqs, TF.matrices, ngs.files, prediction_small.bed)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", paste(missing_files, collapse = ", ")))
    }
    
    # Stage 1: Map features to positive and negative CRMs to build the training set matrix
    crm.feature.list <- mapFeaturesToCRMs(
      URL = 'http://ifbprod.aitorgonzalezlab.org/map_features_to_crms.php',
      positive.bed = positive.bed,
      negative.bed = negative.bed,
      background.freqs = background.freqs,
      pssm = TF.matrices,
      genome = "dm3",
      ngs = ngs.files,
      crm.feature.file = "vignette2_training.crm.features.tab",
      stderr.log.file = "vignette2_training.stderr.log",
      stdout.log.file = "vignette2_training.stdout.log"
    )
    crm.features <- crm.feature.list\$crm.features
    
    # Stage 2: Run the LedPred wrapper function to perform tuning, ranking, selection, and model creation in one step
    cost.vector <- c(1, 3, 10)
    gamma.vector <- c(1, 3, 10)
    ledpred.obj <- LedPred(
      data = crm.features,
      cl = 1,
      ranges = list(cost = cost.vector, gamma = gamma.vector),
      kernel = "linear",
      file.prefix = "vignette2"
    )
    
    # Stage 3: Map features to unknown sequences using the selected features
    prediction.crm.features.obj2 <- mapFeaturesToCRMs(
      URL = 'http://ifbprod.aitorgonzalezlab.org/map_features_to_crms.php',
      positive.bed = prediction_small.bed,
      pssm = TF.matrices,
      background.freqs = background.freqs,
      genome = 'dm3',
      ngs = ngs.files,
      feature.ranking = ledpred.obj\$feature.ranking,
      feature.nb = ledpred.obj\$feature.nb,
      crm.feature.file = "vignette2_pred.crm.features.tab",
      stderr.log.file = "vignette2_pred.stderr.log",
      stdout.log.file = "vignette2_pred.stdout.log"
    )
    prediction.crm.features2 <- prediction.crm.features.obj2\$crm.features
    
    # Stage 4: Score the unknown sequences using the generated model
    # Assigning ledpred.obj to ledpred.list to match the documented code's variable naming
    ledpred.list <- ledpred.obj
    pred.test2 <- scoreData(
      data = prediction.crm.features2,
      model = ledpred.list\$model.obj,
      score.file = "vignette2_prediction.tab"
    )
    
    # Save outputs
    saveRDS(ledpred.obj, "ledpred_model_object.rds")
    saveRDS(pred.test2, "scored_predictions.rds")
    write.csv(pred.test2, "scored_predictions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION":',
        paste0('        ledpred: ', as.character(packageVersion("ledpred")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_in_one_svm_prediction.csv versions.yml
    """
}

workflow BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ positive.bed, negative.bed, background.freq, TF.matrices, ngs.files, prediction_small.bed ] ]

    main:
    BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION(ch_input)

    emit:
    tables   = BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION.out.tables
    plots    = BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION.out.plots
    objects  = BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION.out.objects
    versions = BIOC_LEDPRED_ALL_IN_ONE_SVM_PREDICTION.out.versions
}
