#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LedPred — all_in_one_ledpred
// Build an SVM model and score unknown sequences using the single wrapper function LedPred.
// Input: crm.features, prediction_small.bed, TF.matrices, background.freqs, ngs.files
// Container: quay.io/biocontainers/bioconductor-ledpred:1.44.0--r45hdfd78af_0
// R packages: LedPred
// Bioconductor: 3.20 | R: 4.4
// Requires: LedPred
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Run the all-in-one LedPred function to tune, rank, select features, and build the model. 2. Map features to unknown sequences usin

nextflow.enable.dsl = 2

process BIOC_LEDPRED_ALL_IN_ONE_LEDPRED {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    
    # Load required libraries
    library(LedPred)
    
    # Check and read input files from the working directory
    if (!file.exists("crm.features")) {
      stop("Error: 'crm.features' file is missing from the working directory.")
    }
    crm.features <- tryCatch({
      readRDS("crm.features")
    }, error = function(e) {
      read.table("crm.features", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    })
    
    if (!file.exists("prediction_small.bed")) {
      stop("Error: 'prediction_small.bed' file is missing from the working directory.")
    }
    positive.bed <- "prediction_small.bed"
    
    if (!file.exists("TF.matrices")) {
      stop("Error: 'TF.matrices' file is missing from the working directory.")
    }
    TF.matrices <- "TF.matrices"
    
    if (!file.exists("background.freqs")) {
      stop("Error: 'background.freqs' file is missing from the working directory.")
    }
    background.freqs <- "background.freqs"
    
    if (!file.exists("ngs.files") && !dir.exists("ngs.files")) {
      stop("Error: 'ngs.files' file or directory is missing from the working directory.")
    }
    if (dir.exists("ngs.files")) {
      ngs.files <- list.files("ngs.files", full.names = TRUE)
    } else {
      ngs.files <- "ngs.files"
    }
    
    # Step 1: Run the all-in-one LedPred function to tune, rank, select features, and build the model
    cost.vector <- c(1,3,10)
    gamma.vector <- c(1,3,10)
    
    ledpred.obj=LedPred(data=crm.features, cl=1, ranges = list(cost=cost.vector, gamma=gamma.vector), kernel="linear", file.prefix="vignette2")
    
    # Define ledpred.list to handle the vignette's typo in the scoreData call
    ledpred.list <- ledpred.obj
    
    # Step 2: Map features to unknown sequences using mapFeaturesToCRMs
    prediction.crm.features.obj2 <- mapFeaturesToCRMs(URL = 'http://ifbprod.aitorgonzalezlab.org/map_features_to_crms.php', positive.bed=positive.bed, pssm=TF.matrices, background.freqs=background.freqs, genome='dm3', ngs=ngs.files, feature.ranking=ledpred.obj\$feature.ranking, feature.nb=ledpred.obj\$feature.nb, crm.feature.file = "vignette2_pred.crm.features.tab", stderr.log.file = "vignette2_pred.stderr.log", stdout.log.file = "vignette2_pred.stdout.log")
    prediction.crm.features2 <- prediction.crm.features.obj2\$crm.features
    
    # Step 3: Score unknown sequences using scoreData
    pred.test2 <- scoreData(data=prediction.crm.features2, model=ledpred.list\$model.obj, score.file="vignette2_prediction.tab")
    
    # Save RDS outputs for downstream analysis
    saveRDS(ledpred.obj, "ledpred_obj.rds")
    saveRDS(pred.test2, "pred_test2.rds")

    writeLines(c(
        '"BIOC_LEDPRED_ALL_IN_ONE_LEDPRED":',
        paste0('    LedPred: ', as.character(packageVersion('LedPred')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_in_one_ledpred.csv versions.yml
    """
}

workflow BIOC_LEDPRED_ALL_IN_ONE_LEDPRED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ crm.features, prediction_small.bed, TF.matrices, background.freqs, ngs.files ] ]

    main:
    BIOC_LEDPRED_ALL_IN_ONE_LEDPRED(ch_input)

    emit:
    tables   = BIOC_LEDPRED_ALL_IN_ONE_LEDPRED.out.tables
    plots    = BIOC_LEDPRED_ALL_IN_ONE_LEDPRED.out.plots
    objects  = BIOC_LEDPRED_ALL_IN_ONE_LEDPRED.out.objects
    versions = BIOC_LEDPRED_ALL_IN_ONE_LEDPRED.out.versions
}
