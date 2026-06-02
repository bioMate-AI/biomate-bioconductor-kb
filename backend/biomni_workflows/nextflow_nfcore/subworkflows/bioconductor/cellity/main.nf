#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cellity
// A support vector machine approach to identifying and filtering low quality cells from single-cell RN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cellity/inst/doc/cellity_vignette.R
// Upstream  : caret, ggplot2, knitr
// Downstream: none
//
// Install: BiocManager::install("cellity")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellity"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellity:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellity:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellity_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellity_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellity_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cellity)
    library(jsonlite)


    # --- Eval=true [] ---
    # Key functions: normalise_by_factor, colSums
    library(cellity)
    data(sample_counts)
    data(sample_stats)
    sample_counts_nm <- normalise_by_factor(sample_counts, colSums(sample_counts))

    # --- Eval=true [] ---
    # Key functions: extract_features, requireNamespace, install, org.Hs.eg.db, extra_human_genes, feature_info, human
    sample_features <- extract_features(sample_counts_nm, sample_stats)
    # --- Eval=true [] ---
    # Key functions: assess_cell_quality_PCA
    sample_features_all <- sample_features[[1]]
    sample_qual_pca <- assess_cell_quality_PCA(sample_features_all)
    data(training_mES_features)
    training_mES_features_all <- training_mES_features[[1]]
    training_quality_PCA_allF <- assess_cell_quality_PCA(
      training_mES_features_all, file = "./training_quality_PCA_allF.pdf")

    # --- Eval=true [] ---
    # Key functions: requireNamespace, confusionMatrix, caret, assess_cell_quality_PCA
    if (requireNamespace("caret", quietly = TRUE)) {
      library(caret)
      data(training_mES_labels)
      lvs <- c("0", "1")
      truth <- factor(training_mES_labels[,2],levels = rev(lvs))
      pred <- factor(training_quality_PCA_allF[,2], levels = rev(lvs))
      confusionMatrix(pred, truth)
    }
    training_mES_features_common <- training_mES_features[[2]]
    training_quality_PCA_commonF <- assess_cell_quality_PCA(
      training_mES_features_common, file = "./training_quality_PCA_commonF.pdf")

    # --- Eval=true [] ---
    # Key functions: requireNamespace, confusionMatrix, caret
    if (requireNamespace("caret", quietly = TRUE)) {
      pred <- factor(training_quality_PCA_commonF[,2], levels = rev(lvs))
      confusionMatrix(pred, truth)
    }
    data(mES1_features)
    data(mES1_labels)

    # --- Eval=true [] ---
    # Key functions: assess_cell_quality_SVM, requireNamespace, confusionMatrix, caret
    data(param_mES_all)
    mES1_features_all <- mES1_features[[1]]
    mES1_quality_SVM <- assess_cell_quality_SVM(
      training_mES_features_all, training_mES_labels[,2], param_mES_all, 
      mES1_features_all)
    if (requireNamespace("caret", quietly = TRUE)) {
      truth <- factor(mES1_labels[,2],levels = rev(lvs))
      pred <- factor(mES1_quality_SVM[,2], levels = rev(lvs))
      confusionMatrix(pred, truth)
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellity_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellity_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellity_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLITY:", paste0("    cellity: ", packageVersion("cellity"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellity_results.csv
    touch ${prefix}_cellity_output.rds
    echo "BIOC_CELLITY:" > versions.yml
    echo "    cellity: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLITY(ch_input)

    emit:
    results  = BIOC_CELLITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLITY.out.versions  // channel: path(versions.yml)
}
