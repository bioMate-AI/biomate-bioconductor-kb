#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SIAMCAT — holdout_testing
// Train a machine learning model on a discovery dataset and apply it to an independent external holdout dataset using frozen normalization.
// Input: fn.feat.fr, fn.meta.fr, fn.feat.cn, fn.meta.cn
// Container: quay.io/biocontainers/bioconductor-siamcat:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SIAMCAT
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize discovery and holdout SIAMCAT objects
//  * 2. [Core Analysis] Filter discovery features
//  * 3. [Core Analysis] Normalize discovery features
//  * 4. [Input & Preparation] Prepare cross-validation on discovery data
//  * 5. [Core Analysis] Train model on discovery data
//  * 6. [Core Analysis] Make discovery predictions and evaluate
//  * 7. [Core Analysis] Normalize holdout features using frozen discovery parameters
//  * 8. [Core Analysis] Make holdout predictions
//  * 9. [Core Analysis] Evaluate holdout predictions
//  * 10. [Core Analysis] Compare model performances

nextflow.enable.dsl = 2

process BIOC_SIAMCAT_HOLDOUT_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("SIAMCAT")
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
    library(SIAMCAT)
    
    # Define input file paths as specified
    fn.feat.fr <- "fn.feat.fr"
    fn.meta.fr <- "fn.meta.fr"
    fn.feat.cn <- "fn.feat.cn"
    fn.meta.cn <- "fn.meta.cn"
    
    # Read discovery dataset
    feat.fr <- read.table(fn.feat.fr, sep='\t', header=TRUE, row.names=1, quote="", check.names=FALSE, stringsAsFactors=FALSE)
    feat.fr.rel <- prop.table(as.matrix(feat.fr), 2)
    meta.fr <- read.table(fn.meta.fr, sep='\t', header=TRUE, row.names=1, quote="", check.names=FALSE, stringsAsFactors=FALSE)
    
    # Read holdout dataset
    feat.cn <- read.table(fn.feat.cn, sep='\t', header=TRUE, row.names=1, quote="", check.names=FALSE, stringsAsFactors=FALSE)
    feat.cn.rel <- prop.table(as.matrix(feat.cn), 2)
    meta.cn <- read.table(fn.meta.cn, sep='\t', header=TRUE, row.names=1, quote="", check.names=FALSE, stringsAsFactors=FALSE)
    
    # 1. Initialize discovery and holdout SIAMCAT objects
    siamcat.fr <- siamcat(feat=feat.fr.rel, meta=meta.fr, label='Group', case='CRC')
    siamcat.cn <- siamcat(feat=feat.cn.rel, meta=meta.cn, label='Group', case='CRC')
    
    # 2. Filter discovery features
    siamcat.fr <- filter.features( siamcat.fr, filter.method = 'abundance', cutoff = 0.001, rm.unmapped = TRUE, verbose=2 )
    
    # 3. Normalize discovery features
    siamcat.fr <- normalize.features( siamcat.fr, norm.method = "log.std", norm.param = list(log.n0 = 1e-06, sd.min.q = 0.1), verbose = 2 )
    
    # 4. Prepare cross-validation on discovery data
    siamcat.fr <- create.data.split( siamcat.fr, num.folds = 5, num.resample = 2 )
    
    # 5. Train model on discovery data
    siamcat.fr <- train.model( siamcat.fr, method = "lasso" )
    
    # 6. Make discovery predictions and evaluate
    siamcat.fr <- make.predictions(siamcat.fr)
    siamcat.fr <- evaluate.predictions(siamcat.fr)
    
    # 7. Normalize holdout features using frozen discovery parameters
    siamcat.cn <- normalize.features(siamcat.cn, norm.param=norm_params(siamcat.fr), feature.type='original', verbose = 2)
    
    # 8. Make holdout predictions
    siamcat.cn <- make.predictions( siamcat = siamcat.fr, siamcat.holdout = siamcat.cn, normalize.holdout = FALSE)
    
    # 9. Evaluate holdout predictions
    siamcat.cn <- evaluate.predictions(siamcat.cn)
    
    # 10. Compare model performances and save evaluation plot
    pdf("model_evaluation_comparison.pdf", width=8, height=6)
    model.evaluation.plot('FR-CRC'=siamcat.fr, 'CN-CRC'=siamcat.cn, colours=c('dimgrey', 'orange'))
    dev.off()
    
    # Save SIAMCAT objects for downstream use
    saveRDS(siamcat.fr, "siamcat_fr_results.rds")
    saveRDS(siamcat.cn, "siamcat_cn_results.rds")
    
    # Export predictions to CSV files
    tryCatch({
      pred.fr <- pred_matrix(siamcat.fr)
      write.csv(pred.fr, "predictions_discovery.csv", row.names=TRUE)
    }, error = function(e) {
      message("Could not export discovery predictions: ", e\$message)
    })
    
    tryCatch({
      pred.cn <- pred_matrix(siamcat.cn)
      write.csv(pred.cn, "predictions_holdout.csv", row.names=TRUE)
    }, error = function(e) {
      message("Could not export holdout predictions: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SIAMCAT_HOLDOUT_TESTING":',
        paste0('    SIAMCAT: ', as.character(packageVersion('SIAMCAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_holdout_testing.csv versions.yml
    """
}

workflow BIOC_SIAMCAT_HOLDOUT_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fn.feat.fr, fn.meta.fr, fn.feat.cn, fn.meta.cn ] ]

    main:
    BIOC_SIAMCAT_HOLDOUT_TESTING(ch_input)

    emit:
    tables   = BIOC_SIAMCAT_HOLDOUT_TESTING.out.tables
    plots    = BIOC_SIAMCAT_HOLDOUT_TESTING.out.plots
    objects  = BIOC_SIAMCAT_HOLDOUT_TESTING.out.objects
    versions = BIOC_SIAMCAT_HOLDOUT_TESTING.out.versions
}
