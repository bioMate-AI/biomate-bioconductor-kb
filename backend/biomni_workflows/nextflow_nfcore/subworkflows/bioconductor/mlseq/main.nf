#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MLSeq
// This package applies several machine learning methods, including SVM, bagSVM, Random Forest and CART
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MLSeq/inst/doc/MLSeq.R
// Upstream  : DESeq2, VennDiagram, caret, edgeR, knitr
// Downstream: none
//
// Install: BiocManager::install("MLSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MLSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mlseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mlseq:2.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mlseq:2.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mlseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mlseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mlseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MLSeq)
    library(DataFrame)
    library(jsonlite)

    # --- Data Preparation [Data Preparation] ---
    # Key functions: DataFrame, DESeqDataSetFromMatrix
    filepath <- system.file("extdata/cervical.txt", package = "MLSeq")
    cervical <- read.table(filepath, header = TRUE)
    class_lbls <- DataFrame(condition = factor(rep(c("N", "T"), c(29, 29))))
    vars <- sort(apply(cervical, 1, var, na.rm = TRUE), decreasing = TRUE)
    data_sub <- cervical[names(vars)[1:100], ]
    nTest <- ceiling(ncol(data_sub) * 0.3)
    ind <- 1:nTest
    data.train <- as.matrix(data_sub[, -ind] + 1)
    data.test <- as.matrix(data_sub[, ind] + 1)
    classtr <- DataFrame(condition = class_lbls[-ind, ])
    classts <- DataFrame(condition = class_lbls[ind, ])
    data.trainS4 <- DESeqDataSetFromMatrix(countData = data.train,
                                           colData = classtr,
                                           design = formula(~condition))
    data.testS4 <- DESeqDataSetFromMatrix(countData = data.test,
                                          colData = classts,
                                          design = formula(~condition))

    # --- Model Training [Model Training] ---
    # Key functions: classify, discreteControl, voomControl
    ctrl.discrete <- discreteControl(method = "repeatedcv", number = 5,
                                     repeats = 2, tuneLength = 10)
    ctrl.voom <- voomControl(method = "repeatedcv", number = 5,
                             repeats = 2, tuneLength = 10)
    fit.plda <- classify(data = data.trainS4, method = "PLDA",
                         normalize = "deseq", ref = "T",
                         control = ctrl.discrete)
    fit.voomDLDA <- classify(data = data.trainS4, method = "voomDLDA",
                             normalize = "deseq", ref = "T",
                             control = ctrl.voom)

    # --- Model Prediction and Evaluation [Model Prediction and Evaluation] ---
    # Key functions: predict, trained, selectedGenes
    pred.plda <- predict(fit.plda, data.testS4)
    pred.voomDLDA <- predict(fit.voomDLDA, data.testS4)
    trained_plda <- trained(fit.plda)
    genes_plda <- selectedGenes(fit.plda)
    actual <- data.testS4$condition
    acc_plda <- sum(diag(table(pred.plda, actual))) / length(actual)
    acc_voom <- sum(diag(table(pred.voomDLDA, actual))) / length(actual)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mlseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mlseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mlseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MLSEQ:", paste0("    mlseq: ", packageVersion("MLSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mlseq_results.csv
    touch ${prefix}_mlseq_output.rds
    echo "BIOC_MLSEQ:" > versions.yml
    echo "    mlseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MLSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MLSEQ(ch_input)

    emit:
    results  = BIOC_MLSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MLSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MLSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MLSEQ.out.versions  // channel: path(versions.yml)
}
