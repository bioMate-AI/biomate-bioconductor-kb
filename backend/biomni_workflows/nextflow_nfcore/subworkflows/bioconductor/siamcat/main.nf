#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SIAMCAT — standard_association_and_ml_pipeline
// Perform feature filtering, association testing, confounder checking, and build/evaluate a machine learning model on a single metagenomic dataset.
// Input: feat_crc_zeller, meta_crc_zeller
// Container: quay.io/biocontainers/bioconductor-siamcat:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SIAMCAT
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create label object
//  * 2. [Core Analysis] Initialize SIAMCAT object
//  * 3. [Core Analysis] Filter features
//  * 4. [Visualization & Output] Check associations and plot
//  * 5. [Core Analysis] Check confounders
//  * 6. [Core Analysis] Normalize features
//  * 7. [Input & Preparation] Prepare cross-validation
//  * 8. [Core Analysis] Train model
//  * 9. [Core Analysis] Make predictions
//  * 10. [Core Analysis] Evaluate predictions
//  * 11. [Visualization & Output] Plot evaluation and interpretation

nextflow.enable.dsl = 2

process BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE {
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
    
    # Load required libraries
    library(SIAMCAT)
    
    # Helper function to robustly read the user input files from the working directory
    read_input_file <- function(base_name) {
      # Check for various common extensions in the working directory
      extensions <- c("", ".rds", ".tsv", ".csv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
            return(read.csv(file_path, row.names = 1, check.names = FALSE, sep = ","))
          } else {
            # Default to tab-separated for typical metagenomic matrices
            return(read.table(file_path, sep = "\t", header = TRUE, row.names = 1, check.names = FALSE, quote = ""))
          }
        }
      }
      stop(paste("Error: Input file for", base_name, "not found in the working directory."))
    }
    
    # 1. Read User Input Files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    feat.crc.zeller <- read_input_file("feat_crc_zeller")
    meta.crc.zeller <- read_input_file("meta_crc_zeller")
    
    # Ensure features are in matrix format if read as data.frame
    if (is.data.frame(feat.crc.zeller)) {
      feat.crc.zeller <- as.matrix(feat.crc.zeller)
    }
    
    # 2. Execute SIAMCAT Workflow (reproducing documented code exactly)
    label.crc.zeller <- create.label(meta=meta.crc.zeller, label='Group', case='CRC')
    
    sc.obj <- siamcat(feat=feat.crc.zeller, label=label.crc.zeller, meta=meta.crc.zeller)
    
    sc.obj <- filter.features(sc.obj, filter.method = 'abundance', cutoff = 0.001)
    
    sc.obj <- check.associations(sc.obj, log.n0 = 1e-06, alpha = 0.05)
    
    # Wrap plotting functions without explicit fn.plot in a pdf device to prevent headless environment errors
    pdf("association_plot.pdf", width = 10, height = 8)
    association.plot(sc.obj, sort.by = 'fc', panels = c('fc', 'prevalence', 'auroc'))
    dev.off()
    
    check.confounders(sc.obj, fn.plot = 'confounder_plots.pdf', meta.in = NULL, feature.type = 'filtered')
    
    sc.obj <- normalize.features(sc.obj, norm.method = "log.unit", norm.param = list(log.n0 = 1e-06, n.p = 2,norm.margin = 1))
    
    sc.obj <- create.data.split(sc.obj, num.folds = 5, num.resample = 2)
    
    sc.obj <- train.model(sc.obj, method = "lasso")
    
    sc.obj <- make.predictions(sc.obj)
    
    sc.obj <- evaluate.predictions(sc.obj)
    
    pdf("evaluation_plot.pdf", width = 8, height = 8)
    model.evaluation.plot(sc.obj)
    dev.off()
    
    model.interpretation.plot(sc.obj, fn.plot = 'interpretation.pdf', consens.thres = 0.5, limits = c(-3, 3), heatmap.type = 'zscore')
    
    # 3. Save meaningful outputs to the working directory
    saveRDS(sc.obj, file = "siamcat_final_object.rds")
    
    # Export predictions matrix if available
    if (!is.null(pred_matrix(sc.obj))) {
      write.csv(pred_matrix(sc.obj), file = "predictions_matrix.csv", row.names = TRUE)
    }
    
    # Export evaluation data if available
    if (!is.null(eval_data(sc.obj))) {
      eval_list <- eval_data(sc.obj)
      if ("roc" %in% names(eval_list)) {
        write.csv(as.data.frame(eval_list\$roc), file = "evaluation_roc_data.csv", row.names = FALSE)
      }
    }

    writeLines(c(
        '"BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE":',
        paste0('    SIAMCAT: ', as.character(packageVersion('SIAMCAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_association_and_ml_pipeline.csv versions.yml
    """
}

workflow BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ feat_crc_zeller, meta_crc_zeller ] ]

    main:
    BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE.out.tables
    plots    = BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE.out.plots
    objects  = BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE.out.objects
    versions = BIOC_SIAMCAT_STANDARD_ASSOCIATION_AND_ML_PIPELINE.out.versions
}
