#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cellity — svm_based_quality_classification
// Classify low-quality cells using a supervised SVM ensemble model trained on reference datasets.
// Input: gene_counts.tsv, read_stats.tsv, training_features.RData, training_labels.RData, hyperparameters.RData
// Container: quay.io/biocontainers/bioconductor-cellity:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cellity
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize gene expression counts using normalise_by_factor
//  * 2. [Core Analysis] Extract biological and technical features using extract_features
//  * 3. [Core Analysis] Classify cell quality using assess_cell_quality_SVM with training features, training labels, and optimized hyperparameters

nextflow.enable.dsl = 2

process BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION {
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
    .bm_deps <- c("cellity")
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
    library(cellity)
    
    # 1. Read User Input Files
    # Read gene expression counts (Genes x Cells)
    sample_counts_df <- read.delim("gene_counts.tsv", header = TRUE, row.names = 1, check.names = FALSE)
    sample_counts <- as.matrix(sample_counts_df)
    
    # Read read statistics (Cells x Metrics)
    sample_stats_df <- read.delim("read_stats.tsv", header = TRUE, row.names = 1, check.names = FALSE)
    sample_stats <- as.matrix(sample_stats_df)
    
    # Load training features
    env_feats <- new.env()
    load("training_features.RData", envir = env_feats)
    if ("training_mES_features_all" %in% names(env_feats)) {
      training_mES_features_all <- env_feats\$training_mES_features_all
    } else {
      training_mES_features_all <- env_feats[[names(env_feats)[1]]]
    }
    
    # Load training labels
    env_labels <- new.env()
    load("training_labels.RData", envir = env_labels)
    if ("training_mES_labels" %in% names(env_labels)) {
      training_mES_labels <- env_labels\$training_mES_labels
    } else {
      training_mES_labels <- env_labels[[names(env_labels)[1]]]
    }
    
    # Load hyperparameters
    env_params <- new.env()
    load("hyperparameters.RData", envir = env_params)
    if ("param_mES_all" %in% names(env_params)) {
      param_mES_all <- env_params\$param_mES_all
    } else {
      param_mES_all <- env_params[[names(env_params)[1]]]
    }
    
    # 2. Execute Documented Workflow
    # Normalize gene expression counts
    sample_counts_nm <- normalise_by_factor(sample_counts, colSums(sample_counts))
    
    # Extract biological and technical features
    sample_features <- extract_features(sample_counts_nm, sample_stats)
    
    # Bridge the extracted features to the documented variable name
    mES1_features <- sample_features
    
    # Extract the "all" features subset
    mES1_features_all <- mES1_features[[1]]
    
    # Classify cell quality using SVM ensemble
    mES1_quality_SVM <- assess_cell_quality_SVM(
      training_mES_features_all, training_mES_labels[,2], param_mES_all, 
      mES1_features_all)
    
    # 3. Write Outputs
    write.csv(mES1_quality_SVM, file = "mES1_quality_SVM_results.csv", row.names = TRUE)
    saveRDS(mES1_quality_SVM, file = "mES1_quality_SVM_results.rds")

    writeLines(c(
        '"BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION":',
        paste0('    cellity: ', as.character(packageVersion('cellity')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_svm_based_quality_classification.csv versions.yml
    """
}

workflow BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts.tsv, read_stats.tsv, training_features.RData, training_labels.RData, hyperparameters.RData ] ]

    main:
    BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION.out.tables
    plots    = BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION.out.plots
    objects  = BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION.out.objects
    versions = BIOC_CELLITY_SVM_BASED_QUALITY_CLASSIFICATION.out.versions
}
